#!/bin/bash
 ##############################################################################
 #                      parabola-riscv64-bootstrap                            #
 #                                                                            #
 #    Copyright (C) 2018  Andreas Grapentin                                   #
 #                                                                            #
 #    This program is free software: you can redistribute it and/or modify    #
 #    it under the terms of the GNU General Public License as published by    #
 #    the Free Software Foundation, either version 3 of the License, or       #
 #    (at your option) any later version.                                     #
 #                                                                            #
 #    This program is distributed in the hope that it will be useful,         #
 #    but WITHOUT ANY WARRANTY; without even the implied warranty of          #
 #    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the           #
 #    GNU General Public License for more details.                            #
 #                                                                            #
 #    You should have received a copy of the GNU General Public License       #
 #    along with this program.  If not, see <http://www.gnu.org/licenses/>.   #
 ##############################################################################

package_build() {
  local pkgname="$3"

  deptree_is_satisfyable "$pkgname" || return 0

  msg "makepkg: $pkgname"
  msg "  remaining packages: $(wc -l < "$DEPTREE")"

  prepare_makepkgdir "$MAKEPKGDIR/$pkgname" || return

  local res=0
  "$1" "$pkgname" 2>&1 | tee .MAKEPKGLOG
  res="${PIPESTATUS[0]}"

  popd >/dev/null || return

  if [ "$res" -ne 0 ]; then
    notify -c error "${pkgname//_/\\_}" -h string:document:"$MAKEPKGDIR/$pkgname/.MAKEPKGLOG"
    if [ -f "$TOPBUILDDIR/.KEEP_GOING" ]; then
      sed -i "s/^$pkgname : \\[/& FIXME/" "$DEPTREE"
    else
      return "$res"
    fi
  fi

  deptree_is_satisfyable "$pkgname" || return 0

  "$2" "$pkgname" || return

  deptree_remove "$pkgname"

  local full curr
  full=$(wc -l < "$DEPTREE".FULL)
  curr=$((full - $(wc -l < "$DEPTREE")))
  notify -c success -u low "*$curr/$full* ${pkgname//_/\\_}"
}

packages_build_all() {
  while [ -s "$DEPTREE" ]; do
    local pkgname pkgarch
    pkgname=$(deptree_next) \
      || { error -n "could not resolve dependencies"; return "$ERROR_MISSING"; }

    package_build "$1" "$2" "$pkgname" || return
  done
}

package_reuse_upstream() {
  local dep
  for dep in $(pkgdeps "$1"); do
    deptree_check_depend "$1" "$dep" || return
  done
  deptree_is_satisfyable "$1" || return 0

  check_pkgfile "$PKGPOOL" "$1" && return

  local pkgarch
  pkgarch=$(pkgarch "$1")

  case "$pkgarch" in
    any)
      pacman -Sddw --noconfirm --cachedir "$PKGDEST" "$1" || return
      ;;
    *)
      pacman -Sddw --noconfirm --cachedir . "$1" || return
      local pkgdir="$MAKEPKGDIR/$1/pkg/$1"
      local pkgfiles pkgfile
      pkgfiles=( "$1"-*.pkg.tar.xz ); pkgfile="${pkgfiles[0]}"
      mkdir -p "$pkgdir"
      bsdtar -C "$pkgdir" -xf "$pkgfile" || return
      rm "$pkgdir"/.{MTREE,BUILDINFO}
      sed -i "s/arch = .*/arch = $CARCH/" "$pkgdir"/.PKGINFO
      pushd "$pkgdir" >/dev/null || return
      # shellcheck disable=SC2035
      env LANG=C bsdtar -vczf .MTREE --format=mtree \
          --options='!all,use-set,type,uid,gid,mode,time,size,md5,sha256,link' \
        .PKGINFO *
      # shellcheck disable=SC2035
      env LANG=C bsdtar -vcf - .MTREE .PKGINFO * | xz -c -z - > \
        "$PKGDEST/${pkgfile%-*}-$CARCH.pkg.tar.xz" || return
      popd >/dev/null || return
      ;;
  esac
}

package_enable_arch() {
  sed -i "/arch=(.*\\bany\\b.*)/!s/arch=([^)]*/& $1/" PKGBUILD

  # force regeneration of .SRCINFO
  rm -f .SRCINFO
}

package_has_patch() {
  local OPTIND o p=''
  while getopts "p:" o; do
    case "$o" in
      p) p="-$OPTARG" ;;
      *) die -e "$ERROR_INVOCATION" "Usage: ${FUNCNAME[0]} [-p prefix] pkgname" ;;
    esac
  done
  shift $((OPTIND-1))

  local pkgbase
  pkgbase=$(srcinfo_pkgbase) || return

  local patch="$SRCDIR/patches/$pkgbase$p".patch
  [ -f "$patch" ] || return "$ERROR_MISSING"
}

package_patch() {
  local OPTIND o p='' r=no
  while getopts "p:r" o; do
    case "$o" in
      p) p="-$OPTARG" ;;
      r) r=yes ;;
      *) die -e "$ERROR_INVOCATION" "Usage: ${FUNCNAME[0]} [-p prefix] [-r] pkgname" ;;
    esac
  done
  shift $((OPTIND-1))

  local pkgbase
  pkgbase=$(srcinfo_pkgbase) || return

  local patch="$SRCDIR/patches/$pkgbase$p".patch
  local badpatch="$SRCDIR/patches/$pkgname$p".patch

  ln -s "$patch" .PATCH

  echo -n "checking for $(basename "$patch") ... "
  local have_patch=yes
  if [ ! -f "$patch" ]; then
    have_patch=no
    if [ -f "$badpatch" ]; then
      have_patch="$(basename "$badpatch") (renaming...)"
      mv "$badpatch" "$patch" || return
    fi
  fi
  echo "$have_patch (needed: $r)"

  [ "x$r" == "xyes" ] && [ ! -e "$patch" ] && return "$ERROR_MISSING"

  cp PKGBUILD{,.orig}
  [ ! -e "$patch" ] || patch -Np1 -i "$patch" || return
  cp PKGBUILD{,.in}

  # force regeneration of .SRCINFO
  rm -f .SRCINFO
}

package_import_keys() {
  local keys k
  keys="$(srcinfo_validpgpkeys)"
  for k in $keys; do
    check_gpgkey "$k" && continue
    if ! retry -n 5 -s 60 sudo -u "$SUDO_USER" gpg --recv-keys "$k"; then
      error -n "failed to import key '$k'"
      return "$ERROR_KEYFAIL"
    fi
  done
}

