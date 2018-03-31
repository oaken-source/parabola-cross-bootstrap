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

# shellcheck source=src/stage4/makepkg.sh
. "$TOPSRCDIR"/stage4/makepkg.sh
# shellcheck source=src/stage4/chroot.sh
. "$TOPSRCDIR"/stage4/chroot.sh

stage4_makepkg() {
  package_fetch_upstream_pkgfiles "$1" || return
  package_import_keys "$1" || return
  package_patch "$1" || return

  # substitute common variables
  sed "s#@MULTILIB@#${MULTILIB:-disable}#g" \
    PKGBUILD.in > PKGBUILD

  package_enable_arch "$CARCH"

  # check built dependencies
  local dep
  for dep in $(srcinfo_builddeps -n); do
    deptree_check_depend "$1" "$dep" || return
  done
  for dep in $(srcinfo_rundeps "$1"); do
    deptree_check_depend "$1" "$dep" || return
  done

  # postpone build if necessary
  deptree_is_satisfyable "$1" || return 0

  # don't rebuild if already exists
  check_pkgfile "$PKGPOOL" "$1" && return

  # disable checkdepends
  echo "checkdepends=()" >> PKGBUILD

  # regular build otherwise
  "$BUILDDIR/libremakepkg-$CARCH.sh" -n "$CHOST"-stage4 || return
}

stage4_package_build() {
  local pkgarch
  pkgarch=$(pkgarch "$1") || return

  # clean staging
  rm -f "$PKGDEST"/*

  if [ "x$pkgarch" == "xany" ] || [ "x$1" == "xca-certificates-mozilla" ]; then
    package_reuse_upstream "$1" || return
  else
    stage4_makepkg "$1" || return
  fi

  # postpone on unmet dependencies
  deptree_is_satisfyable "$1" || return 0

  # release the package
  local pkgfile pkgname pkgrepo
  for pkgfile in "$PKGDEST"/*; do
    pkgname="${pkgfile%-*-*-*}"
    pkgrepo=$(package_get_upstream_repo "$pkgname")
    pushd "$PKGDEST/../$pkgrepo/os/$CARCH" >/dev/null || return

    ln -fs ../../../pool/"$(basename "$pkgfile")" "$(basename "$pkgfile")"
    mv "$pkgfile" "$PKGPOOL"
    repo-add -qR "$pkgrepo.db.tar.gz" "$(basename "$pkgfile")"

    popd >/dev/null || return
  done
}

stage4_package_install() {
  local pkgfile
  pkgfile=$(find "$PKGPOOL" -regex "^.*/$1-[^-]*-[^-]*-[^-]*\\.pkg\\.tar\\.xz\$" | head -n1)
  [ -n "$pkgfile" ] || { error "$1: pkgfile not found"; return "$ERROR_MISSING"; }

  yes | librechroot \
      -n "$CHOST-stage4" \
      -C "$BUILDDIR"/config/pacman.conf \
      -M "$BUILDDIR"/config/makepkg.conf \
    run pacman -Udd /repos/pool/"$(basename "$pkgfile")" || return
  yes | librechroot \
      -n "$CHOST-stage4" \
      -C "$BUILDDIR"/config/pacman.conf \
      -M "$BUILDDIR"/config/makepkg.conf \
    run pacman -Syyuu || return
}

stage4() {
  msg -n "Entering Stage 4"

  local groups=(base-devel)

  export BUILDDIR="$TOPBUILDDIR"/stage4
  export SRCDIR="$TOPSRCDIR"/stage4
  export MAKEPKGDIR="$BUILDDIR"/$CARCH-makepkg
  export DEPTREE="$BUILDDIR"/DEPTREE
  export PKGDEST="$BUILDDIR"/packages/staging
  export PKGPOOL="$BUILDDIR"/packages/pool
  export LOGDEST="$BUILDDIR"/makepkglogs
  export DEPPATH=("$PKGPOOL" "${BUILDDIR/stage4/stage3}/packages/$CARCH")

  mkdir -p "$PKGDEST" "$PKGPOOL" "$LOGDEST"
  chown "$SUDO_USER" "$PKGDEST" "$PKGPOOL" "$LOGDEST"

  binfmt_enable

  prepare_stage4_makepkg || die -e "$ERROR_BUILDFAIL" "failed to prepare $CARCH makepkg"
  prepare_stage4_chroot || die -e "$ERROR_BUILDFAIL" "failed to prepare $CARCH chroot"
  prepare_deptree "${groups[@]}" || die -e "$ERROR_BUILDFAIL" "failed to prepare DEPTREE"

  echo "remaining pkges: $(wc -l < "$DEPTREE") / $(wc -l < "$DEPTREE".FULL)"
  if [ -s "$DEPTREE" ]; then
    check_exe -r librechroot libremakepkg

    # build packages from deptree
    packages_build_all stage4_package_build stage4_package_install || return
  fi

  # cleanup
  umount_stage4_chrootdir
}
