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

set -euo pipefail

msg "Entering Stage 2"

# set a bunch of convenience variables
_builddir="$topbuilddir"/stage2
_srcdir="$topsrcdir"/stage2
_chrootdir="$_builddir"/$CARCH-root
_makepkgdir="$_builddir"/$CARCH-makepkg
_deptree="$_builddir"/DEPTREE
_sysroot="$($CHOST-gcc --print-sysroot)"
_buildhost="$(gcc -dumpmachine)"
_groups="base-devel"
_pkgdest="$_chrootdir"/packages/$CARCH
_logdest="$_builddir"/makepkglogs

# check for required programs
check_exe awk
check_exe bsdtar
check_exe pacman
check_exe sed
check_exe tar

# required for dbus
check_file /usr/share/aclocal/ax_append_flag.m4

# prepare for the build
. "$_srcdir"/prepare_chroot.sh
. "$_srcdir"/prepare_makepkg.sh
. "$_srcdir"/prepare_deptree.sh

msg "starting $CARCH cross-build"

# keep building packages until the deptree is empty
while [ -s "$_deptree" ]; do
  # grab one without unfulfilled dependencies
  _pkgname=$(grep '\[ *\]' "$_deptree" | head -n1 | awk '{print $1}') || true
  [ -n "$_pkgname" ] || die "could not resolve dependencies. exiting."

  _pkgarch=$(pacman -Si $_pkgname | grep '^Architecture' | awk '{print $3}')

  # set arch to $CARCH, unless it is any
  [ "x$_pkgarch" == "xany" ] || _pkgarch=$CARCH

  msg "makepkg: $_pkgname"
  msg "  remaining packages: $(cat "$_deptree" | wc -l)"

  echo -n "checking for built $_pkgname package ... "
  pacman --config "$_chrootdir"/etc/pacman.conf -r "$_chrootdir" -Syyi $_pkgname &>/dev/null \
    && _have_pkg=yes || _have_pkg=no
  echo $_have_pkg

  if [ "x$_have_pkg" == "xno" ]; then
    # prepare directories
    _pkgdir="$_makepkgdir"/$_pkgname/pkg/$_pkgname
    rm -rf "$_makepkgdir"/$_pkgname
    mkdir -pv "$_makepkgdir"/$_pkgname
    pushd "$_makepkgdir"/$_pkgname >/dev/null

    if [ "x$_pkgarch" == "xany" ]; then
      # repackage arch=(any) packages
      _pkgver=$(pacman -Si $_pkgname | grep '^Version' | awk '{print $3}')
      pacman -Sw --noconfirm --cachedir "$_pkgdest" $_pkgname
      ln -s "$_pkgdest"/$_pkgname-$_pkgver-any.pkg.tar.xz \
        "$_makepkgdir"/$_pkgname/$_pkgname-$_pkgver-any.pkg.tar.xz
    elif [ "x$_pkgname" == "xca-certificates-mozilla" ]; then
      # repackage ca-certificates-mozilla to avoid building nss
      _pkgver=$(pacman -Si $_pkgname | grep '^Version' | awk '{print $3}')
      pacman -Sw --noconfirm --cachedir . $_pkgname
      mkdir tmp && bsdtar -C tmp -xf $_pkgname-$_pkgver-*.pkg.tar.xz
      mkdir -p "$_pkgdir"/usr/share/
      cp -rv tmp/usr/share/ca-certificates/ "$_pkgdir"/usr/share/
      cat > "$_pkgdir"/.PKGINFO << EOF
pkgname = $_pkgname
pkgver = $_pkgver
pkgdesc = Mozilla's set of trusted CA certificates
url = https://developer.mozilla.org/en-US/docs/Mozilla/Projects/NSS
builddate = $(date '+%s')
size = 0
arch = $_pkgarch
EOF
      cd "$_pkgdir"
      env LANG=C bsdtar -czf .MTREE \
        --format=mtree \
        --options='!all,use-set,type,uid,gid,mode,time,size,md5,sha256,link' \
        .PKGINFO *
      env LANG=C bsdtar -cf - .MTREE .PKGINFO * | xz -c -z - > \
        "$_pkgdest"/$_pkgname-$_pkgver-$_pkgarch.pkg.tar.xz
      ln -s "$_pkgdest"/$_pkgname-$_pkgver-$_pkgarch.pkg.tar.xz \
        "$_makepkgdir"/$_pkgname/$_pkgname-$_pkgver-$_pkgarch.pkg.tar.xz
    else
      # acquire the pkgbuild and auxiliary files
      _libre=https://www.parabola.nu/packages/libre/x86_64/$_pkgname/
      _core=https://www.archlinux.org/packages/core/x86_64/$_pkgname/
      _extra=https://www.archlinux.org/packages/extra/x86_64/$_pkgname/
      _community=https://www.archlinux.org/packages/community/x86_64/$_pkgname/
      for url in $_libre $_core $_extra $_community; do
        if ! curl -s $url | grep -iq 'not found'; then
          src=$(curl -s $url | grep -i 'source files' | cut -d'"' -f2 | sed 's#/tree/#/plain/#')
          for link in $(curl -sL $src | grep '^  <li><a href' | cut -d"'" -f2 \
              | sed "s#^#$(echo $src | awk -F/ '{print $3}')#"); do
            wget -q $link -O $(basename ${link%\?*});
          done
          break
        fi
      done

      # patch for cross-compiling
      [ -f "$_srcdir"/patches/$_pkgname.patch ] || die "missing package patch"
      cp PKGBUILD{,.old}
      patch -Np1 -i "$_srcdir"/patches/$_pkgname.patch

      # substitute common variables
      sed -i "s#@TARGET@#$CHOST#g; \
              s#@GCC_MARCH@#$GCC_MARCH#g; \
              s#@GCC_MABI@#$GCC_MABI#g; \
              s#@BUILDHOST@#$_buildhost#g; \
              s#@SYSROOT@#$_sysroot#g; \
              s#@LINUX_ARCH@#$LINUX_ARCH#g" \
        PKGBUILD

      # enable the target CARCH in arch array
      sed -i "s/arch=([^)]*/& $CARCH/" PKGBUILD

      # build the package
      chown -R $SUDO_USER "$_makepkgdir"/$_pkgname
      sudo -u $SUDO_USER \
      "$_builddir"/makepkg-$CARCH.sh -fLC --config "$_builddir"/makepkg-$CARCH.conf \
        --skipchecksums --skippgpcheck --nocheck --nodeps

      # construct pkgver from pkgbuild
      _srcinfo=$(sudo -u $SUDO_USER makepkg --printsrcinfo)
      _pkgver=$(echo "$_srcinfo" | grep 'pkgver =' | head -n1 | awk '{print $3}')
      _pkgrel=$(echo "$_srcinfo" | grep 'pkgrel =' | head -n1 | awk '{print $3}')
      _epoch=$(echo "$_srcinfo" | grep 'epoch =' | head -n1 | awk '{print $3}'): || _epoch=""
      _pkgver="$_epoch$_pkgver-$_pkgrel"
    fi

    popd >/dev/null

    # update pacman cache
    rm -rf "$_chrootdir"/var/cache/pacman/pkg/*
    rm -rf "$_pkgdest"/cross.{db,files}*
    repo-add -q -R "$_pkgdest"/{cross.db.tar.gz,*.pkg.tar.xz}
  fi

  # install in chroot
  set +o pipefail
  yes | pacman --noscriptlet --force --config "$_chrootdir"/etc/pacman.conf \
    -r "$_chrootdir" -Syydd $_pkgname
  set -o pipefail

  # remove pkg from deptree
  sed -i "/^$_pkgname :/d; s/ $_pkgname\b//g" "$_deptree"
done

echo "all packages built."

# unmount sysroot
umount "$_sysroot"/usr
