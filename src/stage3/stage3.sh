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

# shellcheck source=src/stage3/makepkg.sh
. "$TOPSRCDIR"/stage3/makepkg.sh
# shellcheck source=src/stage3/chroot.sh
. "$TOPSRCDIR"/stage3/chroot.sh

stage3_makepkg() {
  local pkgname="${1%-decross}"
  local prefix=()
  [ "x$1" != "x$pkgname" ] && prefix=(-p decross)

  package_fetch_upstream_pkgfiles "$pkgname" || return
  package_import_keys "$pkgname" || return
  package_patch "${prefix[@]}" "$pkgname" || return

  # substitute common variables
  sed "s#@MULTILIB@#${MULTILIB:-disable}#g; \
       s#@GCC_CONFIG_FLAGS@#${GCC_CONFIG_FLAGS[*]}#g" \
    PKGBUILD.in > PKGBUILD

  # prepare the pkgbuild
  package_enable_arch "$CARCH"
  echo "checkdepends=()" >> PKGBUILD

  # check built dependencies
  local dep
  for dep in $(srcinfo_builddeps -n); do
    deptree_check_depend "$1" "$dep" || return
  done
  for dep in $(srcinfo_rundeps "$pkgname"); do
    deptree_check_depend "$1" "$dep" || return
  done

  # postpone build if necessary
  deptree_is_satisfyable "$1" || return 0

  # don't rebuild if already exists
  check_pkgfile "$PKGDEST" "$1" && return

  if [ "x$1" != "x$pkgname" ]; then
    # a bit of magic for -decross builds
    PKGDEST=. "$BUILDDIR/libremakepkg.sh" -n "$CHOST"-stage3 || return
    local pkgfiles pkgfile
    pkgfiles=("$pkgname"-*.pkg.tar.xz); pkgfile="${pkgfiles[0]}"
    mv -v "$pkgfile" "$PKGDEST/${pkgfile/$pkgname/$1}"
  else
    # regular build otherwise
    "$BUILDDIR/libremakepkg.sh" -n "$CHOST"-stage3 || return
  fi
}

stage3_package_build() {
  local pkgarch
  pkgarch=$(pkgarch "${1%-decross}") || return

  if [ "x$pkgarch" == "xany" ] || [ "x$1" == "xca-certificates-mozilla" ]; then
    package_reuse_upstream "$1" || return
  else
    stage3_makepkg "$1" || return
  fi

  # postpone on unmet dependencies
  deptree_is_satisfyable "$1" || return 0

  # update repo
  rm -rf /var/cache/pacman/pkg-"$CARCH"/*
  rm -rf "$PKGDEST"/native.{db,files}*
  repo-add -q -R "$PKGDEST"/{native.db.tar.gz,*.pkg.tar.xz}
}

stage3_package_install() {
  local esc pkgfile
  esc=$(printf '%s\n' "$1" | sed 's:[][\/.^$*]:\\&:g')
  pkgfile=$(find "$PKGPOOL" -regex "^.*/$esc-[^-]*-[^-]*-[^-]*\\.pkg\\.tar\\.xz\$" | head -n1)
  [ -n "$pkgfile" ] || { error "$1: pkgfile not found"; return "$ERROR_MISSING"; }

  yes | librechroot \
      -n "$CHOST-stage3" \
      -C "$BUILDDIR"/config/pacman.conf \
      -M "$BUILDDIR"/config/makepkg.conf \
    run pacman -U /repos/native/"$CARCH"/"$(basename "$pkgfile")" || return
  yes | librechroot \
      -n "$CHOST-stage3" \
      -C "$BUILDDIR"/config/pacman.conf \
      -M "$BUILDDIR"/config/makepkg.conf \
    run pacman -Syyuu || return
}

stage3() {
  msg -n "Entering Stage 3"

  local groups=(base-devel)
  local decross=(bash make)

  export BUILDDIR="$TOPBUILDDIR"/stage3
  export SRCDIR="$TOPSRCDIR"/stage3
  export MAKEPKGDIR="$BUILDDIR"/$CARCH-makepkg
  export DEPTREE="$BUILDDIR"/DEPTREE
  export PKGDEST="$BUILDDIR"/packages/$CARCH
  export PKGPOOL="$PKGDEST"
  export LOGDEST="$BUILDDIR"/makepkglogs
  export DEPPATH=("$PKGDEST" "${PKGDEST/stage3/stage2}")

  mkdir -p "$PKGDEST" "$PKGPOOL" "$LOGDEST"
  chown "$SUDO_USER" "$PKGDEST" "$PKGPOOL" "$LOGDEST"

  binfmt_enable

  prepare_deptree "${groups[@]}" || die -e "$ERROR_BUILDFAIL" "failed to prepare DEPTREE"
  local pkg
  for pkg in "${decross[@]}"; do
    deptree_add_entry "$pkg-decross"
  done
  echo "remaining pkges: $(wc -l < "$DEPTREE") / $(wc -l < "$DEPTREE".FULL)"
  [ -s "$DEPTREE" ] || return 0

  prepare_stage3_makepkg || die -e "$ERROR_BUILDFAIL" "failed to prepare $CARCH makepkg"
  prepare_stage3_chroot || die -e "$ERROR_BUILDFAIL" "failed to prepare $CARCH chroot"

  check_exe -r librechroot libremakepkg

  for pkg in "${decross[@]}"; do
    package_build stage3_package_build stage3_package_install "$pkg-decross" || return
  done

  # build packages from deptree
  packages_build_all stage3_package_build stage3_package_install || return

  # cleanup
  umount_stage3_chrootdir
}
