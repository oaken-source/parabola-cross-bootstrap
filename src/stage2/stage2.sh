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

# shellcheck source=src/stage2/makepkg.sh
. "$TOPSRCDIR"/stage2/makepkg.sh
# shellcheck source=src/stage2/chroot.sh
. "$TOPSRCDIR"/stage2/chroot.sh

stage2_makepkg() {
  package_fetch_upstream_pkgfiles "$1" || return
  package_import_keys "$1" || return
  package_patch -r "$1" || return

  # substitute common variables
  sed "s#@CARCH@#$CARCH#g; \
       s#@CHOST@#$CHOST#g; \
       s#@GCC_MARCH@#$GCC_MARCH#g; \
       s#@GCC_MABI@#$GCC_MABI#g; \
       s#@CARCH32@#${CARCH32:-}#g; \
       s#@CHOST32@#${CHOST32:-}#g; \
       s#@GCC32_MARCH@#${GCC32_MARCH:-}#g; \
       s#@GCC32_MABI@#${GCC32_MABI:-}#g; \
       s#@BUILDHOST@#$(gcc -dumpmachine)#g; \
       s#@SYSROOT@#$SYSROOT#g; \
       s#@LINUX_ARCH@#$LINUX_ARCH#g; \
       s#@MULTILIB@#${MULTILIB:-disable}#g;" \
    PKGBUILD.in > PKGBUILD

  package_enable_arch "$CARCH"

  # check built dependencies
  local dep
  for dep in $(srcinfo_builddeps -nm); do
    deptree_check_depend "$1" "$dep" || return
  done
  for dep in $(srcinfo_rundeps "$1"); do
    deptree_check_depend "$1" "$dep" || return
  done

  # postpone build if necessary
  deptree_is_satisfyable "$1" || return 0

  # don't rebuild if already exists
  check_pkgfile "$PKGDEST" "$1" && return

  # build the package
  runas "$SUDO_USER" \
  "$BUILDDIR"/makepkg-"$CARCH".sh -fLC --config "$BUILDDIR"/makepkg-"$CARCH".conf \
    --nocheck --nodeps --nobuild --noconfirm || return

  if [ "x${REGEN_CONFIG_FRAGMENTS:-no}" == "xyes" ]; then
    url="https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain"
    find src -iname config.sub -print -exec curl "$url;f=config.sub;hb=HEAD" -o {} \; || return
  fi

  runas "$SUDO_USER" \
  "$BUILDDIR"/makepkg-"$CARCH".sh -efL --config "$BUILDDIR"/makepkg-"$CARCH".conf \
    --nocheck --nodeps --noprepare --noconfirm || return
}

stage2_package_build() {
  local pkgarch
  pkgarch=$(pkgarch "$1") || return

  if [ "x$pkgarch" == "xany" ] || [ "x$1" == "xca-certificates-mozilla" ]; then
    package_reuse_upstream "$1" || return
  else
    stage2_makepkg "$1" || return
  fi

  # postpone on unmet dependencies
  deptree_is_satisfyable "$1" || return 0

  # update repo
  rm -rf "$CHROOTDIR"/var/cache/pacman/pkg/*
  rm -rf "$PKGDEST"/cross.{db,files}*
  repo-add -q -R "$PKGDEST"/{cross.db.tar.gz,*.pkg.tar.xz}
}

stage2_package_install() {
  # install in chroot
  yes | pacman --noscriptlet --force --config "$CHROOTDIR"/etc/pacman.conf \
    -r "$CHROOTDIR" -Syydd "$1" || return
}

stage2() {
  msg -n "Entering Stage 2"

  local groups=(base-devel)

  local sysroot
  sysroot="$("$CHOST"-gcc --print-sysroot)"

  export BUILDDIR="$TOPBUILDDIR"/stage2
  export SRCDIR="$TOPSRCDIR"/stage2
  export CHROOTDIR="$BUILDDIR"/$CARCH-root
  export MAKEPKGDIR="$BUILDDIR"/$CARCH-makepkg
  export DEPTREE="$BUILDDIR"/DEPTREE
  export SYSROOT="$sysroot"
  export PKGDEST="$BUILDDIR"/packages/$CARCH
  export PKGPOOL="$PKGDEST"
  export LOGDEST="$BUILDDIR"/makepkglogs
  export DEPPATH=("$PKGDEST")

  mkdir -p "$PKGDEST" "$PKGPOOL" "$LOGDEST"
  chown "$SUDO_USER" "$PKGDEST" "$PKGPOOL" "$LOGDEST"

  binfmt_disable

  prepare_deptree "${groups[@]}" || die -e "$ERROR_BUILDFAIL" "failed to prepare DEPTREE"
  echo "remaining pkges: $(wc -l < "$DEPTREE") / $(wc -l < "$DEPTREE".FULL)"
  [ -s "$DEPTREE" ] || return 0

  prepare_stage2_makepkg || die -e "$ERROR_BUILDFAIL" "failed to prepare $CARCH makepkg"
  prepare_stage2_chroot || die -e "$ERROR_BUILDFAIL" "failed to prepare $CARCH chroot"

  # pull in various tools required to run the scripts or build the packages
  check_exe -r arch-meson asp awk bsdtar git gperf help2man pacman sed svn tar tclsh

  # build packages from deptree
  packages_build_all stage2_package_build stage2_package_install || return

  # cleanup
  umount_stage2_chrootdir
}
