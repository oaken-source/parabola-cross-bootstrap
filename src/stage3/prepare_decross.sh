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

msg "preparing native $CARCH decross'd packages"

# cross-compiled packages con be a bit derpy.
# rebuild a couple of things using native patches

_decross="bash make"

for _pkgname in $_decross; do
  echo -n "checking for $CARCH $_pkgname ... "
  [ -f "$_makepkgdir"/$_pkgname/$_pkgname-*.pkg.tar.xz ] && _have_pkg=yes || _have_pkg=no
  echo $_have_pkg

  if [ "x$_have_pkg" == "xno" ]; then
    _pkgarch=$(pacman -Si $_pkgname | grep '^Architecture' | awk '{print $3}')

    # set arch to $CARCH, unless it is any
    [ "x$_pkgarch" == "xany" ] || _pkgarch=$CARCH

    msg "makepkg: $_pkgname"

    # prepare directories
    _pkgdir="$_makepkgdir"/$_pkgname/pkg/$_pkgname
    rm -rf "$_makepkgdir"/$_pkgname
    mkdir -pv "$_makepkgdir"/$_pkgname
    pushd "$_makepkgdir"/$_pkgname >/dev/null

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

    cp PKGBUILD{,.old}
    patch -Np1 -i "$_srcdir"/patches/$_pkgname-decross.patch

    # substitute common variables
    _config="https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain"
    _config_sub="$_config;f=config.sub;hb=HEAD"
    _config_guess="$_config;f=config.guess;hb=HEAD"
    sed -i "s#@CONFIG_SUB@#curl \"$_config_sub\"#g; \
            s#@CONFIG_GUESS@#curl \"$_config_guess\"#g;" \
      PKGBUILD

    # enable the target CARCH in arch array
    sed -i "s/arch=([^)]*/& $CARCH/" PKGBUILD

    # build the package
    chown -R $SUDO_USER "$_makepkgdir"/$_pkgname
    PKGDEST=. libremakepkg -n $CHOST-stage3

    # install the package
    set +o pipefail
    yes | librechroot \
        -n "$CHOST-stage3" \
        -C "$_builddir"/config/pacman.conf \
        -M "$_builddir"/config/makepkg.conf \
      install-file $_pkgname-*.pkg.tar.xz
    set -o pipefail
  fi
done
