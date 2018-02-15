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

# keep building packages until the deptree is empty
while [ -s "$_deptree" ]; do
  # grab one without unfulfilled dependencies
  _pkgname=$(grep '\[ \]' "$_deptree" | head -n1 | awk '{print $1}')
  [ -n "$_pkgname" ] || die "could not resolve cyclic dependencies. exiting."

  _pkgarch=$(pacman -Si $_pkgname | grep '^Architecture' | awk '{print $3}')
  _pkgdir="$_makepkgdir"/$_pkgname/pkg/$_pkgname

  [ "x$_pkgarch" == "xany" ] || _pkgarch=$_arch

  msg "makepkg: $_pkgname"
  msg "  remaining pkges: $(cat "$_deptree" | wc -l)"

  if [ ! -h "$_makepkgdir"/$_pkgname.pkg.tar.xz ]; then
    rm -rf "$_makepkgdir"/$_pkgname
    mkdir -pv "$_makepkgdir"/$_pkgname
    pushd "$_makepkgdir"/$_pkgname >/dev/null

    if [ "x$_pkgarch" == "xany" ]; then
      # simply reuse arch=(any) packages
      _pkgver=$(pacman -Qi $_pkgname | grep '^Version' | awk '{print $3}')
      pacman -Sw --noconfirm --cachedir . $_pkgname
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

      # [ "x$_pkgname" == "xlibffi" ] && die "stopping."

      [ -f "$_srcdir"/stage1/patches/$_pkgname.patch ] || die "missing package patch"
      patch -Np1 -i "$_srcdir"/stage1/patches/$_pkgname.patch

      # substitute common variables
      sed -i "s#@TARGET@#$_target#" PKGBUILD
      sed -i "s#@ARCH@#$_arch#" PKGBUILD
      sed -i "s#@LINUX_ARCH@#$_linux_arch#" PKGBUILD
      sed -i "s#@CHROOTDIR@#$_chrootdir#" PKGBUILD

      # enable the target arch explicitly
      sed -i "s/arch=([^)]*/& $_arch/" PKGBUILD

      # build the package
      chown -R $SUDO_USER "$_makepkgdir"/$_pkgname
      sudo -u $SUDO_USER \
        "$_makepkgdir"/makepkg-$_arch.sh -C --config "$_makepkgdir"/makepkg-$_arch.conf \
        --skipchecksums --skippgpcheck --nocheck --nodeps 2>&1 | tee makepkg.log

      # construct pkgver from pkgbuild
      _srcinfo=$(sudo -u $SUDO_USER makepkg --printsrcinfo)
      _pkgver=$(echo "$_srcinfo" | grep 'pkgver =' | head -n1 | awk '{print $3}')
      _pkgrel=$(echo "$_srcinfo" | grep 'pkgrel =' | head -n1 | awk '{print $3}')
      _epoch=$(echo "$_srcinfo" | grep 'epoch =' | head -n1 | awk '{print $3}'): || _epoch=""
      _pkgver="$_epoch$_pkgver-$_pkgrel"
    fi

    ln -s "$_makepkgdir"/$_pkgname/$_pkgname-$_pkgver-$_pkgarch.pkg.tar.xz \
      "$_makepkgdir"/$_pkgname.pkg.tar.xz

    popd >/dev/null
  fi

  cp -lv "$(readlink -f "$_makepkgdir"/$_pkgname.pkg.tar.xz)" "$_chrootdir"/packages/$_arch/

  rm -rf "$_chrootdir"/var/cache/pacman/pkg/*
  rm -rf "$_chrootdir"/packages/$_arch/repo.{db,files}*
  repo-add -q -R "$_chrootdir"/packages/$_arch/{repo.db.tar.gz,*.pkg.tar.xz}
  (yes || true) | pacman --noscriptlet --config "$_chrootdir"/etc/pacman.conf \
    -r "$_chrootdir" -Syy $_pkgname

  # remove pkg from deptree
  sed -i "/^$_pkgname :/d; s/ $_pkgname\b//g" "$_deptree"
done

