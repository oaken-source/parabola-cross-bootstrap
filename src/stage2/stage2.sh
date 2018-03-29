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

build_pkg_any() {
  local dep
  for dep in $(pkgdeps "$pkgname"); do
    deptree_check_depends "$pkgname" "$dep" || return
  done
  [ "x$(deptree_next)" != "x$pkgname" ] && return

  check_pkgfile "$PKGDEST" "$pkgname" && return

  pacman -Sddw --noconfirm --cachedir "$PKGDEST" "$pkgname" || return
}

build_pkg_ca-certificates-mozilla() {
  # repackage ca-certificates-mozilla to avoid building nss
  local dep
  for dep in $(pkgdeps "$pkgname"); do
    deptree_check_depends "$pkgname" "$dep" || return
  done
  [ "x$(deptree_next)" != "x$pkgname" ] && return

  check_pkgfile "$PKGDEST" "$pkgname" && return

  local pkgver pkgdir="$MAKEPKGDIR"/$pkgname/pkg/$pkgname
  pkgver=$(pkgver "$pkgname") || return
  pacman -Sddw --noconfirm --cachedir . "$pkgname" || return
  mkdir tmp && bsdtar -C tmp -xf "$pkgname"-*.pkg.tar.xz || return
  mkdir -p "$pkgdir"/usr/share/
  cp -rv tmp/usr/share/ca-certificates/ "$pkgdir"/usr/share/
  cat > "$pkgdir"/.PKGINFO << EOF
pkgname = $pkgname
pkgver = $pkgver
pkgdesc = Mozilla's set of trusted CA certificates
url = https://developer.mozilla.org/en-US/docs/Mozilla/Projects/NSS
builddate = $(date '+%s')
size = 0
arch = $pkgarch
EOF
  cd "$pkgdir" || return
  env LANG=C bsdtar -czf .MTREE \
    --format=mtree \
    --options='!all,use-set,type,uid,gid,mode,time,size,md5,sha256,link' \
    .PKGINFO ./* || return
  env LANG=C bsdtar -cf - .MTREE .PKGINFO ./* | xz -c -z - > \
    "$PKGDEST/$pkgname-$pkgver-$pkgarch.pkg.tar.xz" || return
}

build_stage2_pkg() {
  package_fetch_upstream_pkgfiles "$pkgname" || return
  import_keys || return

  local pkgbase
  pkgbase=$(srcinfo_pkgbase) || return

  # patch for cross-compiling
  cp PKGBUILD{,.old}
  patch -Np1 -i "$SRCDIR"/patches/"$pkgbase".patch || return
  cp PKGBUILD{,.in}

  # substitute common variables
  sed -i \
      "s#@CARCH@#$CARCH#g; \
       s#@CHOST@#$CHOST#g; \
       s#@GCC_MARCH@#$GCC_MARCH#g; \
       s#@GCC_MABI@#$GCC_MABI#g; \
       s#@CARCH32@#${CARCH32:-}#g; \
       s#@CHOST32@#${CHOST32:-}#g; \
       s#@GCC32_MARCH@#${GCC32_MARCH:-}#g; \
       s#@GCC32_MABI@#${GCC32_MABI:-}#g; \
       s#@BUILDHOST@#$BUILDHOST#g; \
       s#@SYSROOT@#$SYSROOT#g; \
       s#@LINUX_ARCH@#$LINUX_ARCH#g; \
       s#@MULTILIB@#${MULTILIB:-disable}#g;" \
    PKGBUILD

  # enable the target CARCH in arch array
  sed -i "s/arch=([^)]*/& $CARCH/" PKGBUILD

  # force regeneration of .SRCINFO
  rm .SRCINFO

  # check built dependencies
  local dep
  for dep in $(srcinfo_builddeps -nm); do
    deptree_check_depends "$pkgname" "$dep" || return
  done
  for dep in $(srcinfo_rundeps "$pkgname"); do
    deptree_check_depends "$pkgname" "$dep" || return
  done

  # postpone build if necessary
  [ "x$(deptree_next)" != "x$pkgname" ] && return

  # don't rebuild if already exists
  check_pkgfile "$PKGDEST" "$pkgname" && return

  # build the package
  sudo -u "$SUDO_USER" \
  "$BUILDDIR"/makepkg-"$CARCH".sh -fLC --config "$BUILDDIR"/makepkg-"$CARCH".conf \
    --nocheck --nodeps --nobuild --noconfirm || return

  if [ "x${REGEN_CONFIG_FRAGMENTS:-no}" == "xyes" ]; then
    url="https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain"
    find src -iname config.sub -print -exec curl "$url;f=config.sub;hb=HEAD" -o {} \; || return
  fi

  sudo -u "$SUDO_USER" \
  "$BUILDDIR"/makepkg-"$CARCH".sh -efL --config "$BUILDDIR"/makepkg-"$CARCH".conf \
    --nocheck --nodeps --noprepare --noconfirm || return
}

build_pkg() {
  local pkgname="$1"
  pkgarch=$(pkgarch "$pkgname") || return

  if [ "x$pkgarch" == "xany" ]; then
    build_pkg_any "$1" || return
  elif [ "x$pkgname" == "xca-certificates-mozilla" ]; then
    build_pkg_ca-certificates-mozilla "$1" || return
  else
    build_stage2_pkg "$1" || return
  fi

  # postpone on unmet dependencies
  [ "x$(deptree_next)" != "x$pkgname" ] && return

  # update pacman cache
  rm -rf "$CHROOTDIR"/var/cache/pacman/pkg/*
  rm -rf "$PKGDEST"/cross.{db,files}*
  repo-add -q -R "$PKGDEST"/{cross.db.tar.gz,*.pkg.tar.xz}
}

stage2() {
  msg -n "Entering Stage 2"

  local sysroot
  sysroot="$("$CHOST"-gcc --print-sysroot)"

  export BUILDDIR="$TOPBUILDDIR"/stage2
  export SRCDIR="$TOPSRCDIR"/stage2
  export CHROOTDIR="$BUILDDIR"/$CARCH-root
  export MAKEPKGDIR="$BUILDDIR"/$CARCH-makepkg
  export DEPTREE="$BUILDDIR"/DEPTREE
  export SYSROOT="$sysroot"
  export BUILDHOST="x86_64-pc-linux-gnu"
  export PKGDEST="$BUILDDIR"/packages/$CARCH
  export LOGDEST="$BUILDDIR"/makepkglogs

  mkdir -p "$PKGDEST" "$LOGDEST"
  chown "$SUDO_USER" "$PKGDEST" "$LOGDEST"

  binfmt_disable

  prepare_makepkg || die -e "$ERROR_BUILDFAIL" "failed to prepare $CARCH makepkg"
  prepare_chroot || die -e "$ERROR_BUILDFAIL" "failed to prepare $CARCH chroot"
  prepare_deptree base-devel || die -e "$ERROR_BUILDFAIL" "failed to prepare DEPTREE"

  echo "remaining pkges: $(wc -l < "$DEPTREE") / $(wc -l < "$DEPTREE".FULL)"
  [ -s "$DEPTREE" ] || return 0

  # pull in various tools required to run the scripts or build the packages
  check_exe -r arch-meson asp awk bsdtar git gperf help2man pacman sed svn tar tclsh

  while [ -s "$DEPTREE" ]; do
    local pkgname pkgarch
    pkgname=$(deptree_next) \
      || die -e "$ERROR_MISSING" "could not resolve dependencies"

    msg "makepkg: $pkgname"
    msg "  remaining packages: $(wc -l < "$DEPTREE")"

    prepare_makepkgdir "$MAKEPKGDIR/$pkgname" || return

    build_pkg "$pkgname" 2>&1 | tee .MAKEPKGLOG
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
      notify -c error "$pkgname" -h string:document:.MAKEPKGLOG
      [ "x$KEEP_GOING" == "xyes" ] || return
      sed -i "s/^$pkgname : \\[/& FIXME/" "$DEPTREE"
    fi

    popd >/dev/null || return

    [ "x$(deptree_next)" != "x$pkgname" ] && continue

    # install in chroot
    yes | pacman --noscriptlet --force --config "$CHROOTDIR"/etc/pacman.conf \
      -r "$CHROOTDIR" -Syydd "$pkgname" || die -e "$ERROR_BUILDFAIL" "failed to install pkg"

    deptree_remove "$pkgname"

    full=$(wc -l < "$DEPTREE".FULL)
    curr=$((full - $(wc -l < "$DEPTREE")))
    notify -c success -u low "*$curr/$full* $pkgname"
  done

  umount_chrootdir
}
