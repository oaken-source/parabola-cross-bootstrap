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
# rebuild a couple of things using native toolchain and custom patches

while grep -q -- -decross "$_deptree"; do
  _pkgname=$(grep -- -decross "$_deptree" | head -n1 | awk '{print $1}')
  _pkgname=${_pkgname%-decross}

  echo -n "checking for $CARCH $_pkgname ... "
  [ -f "$_makepkgdir"/$_pkgname-decross/$_pkgname-*.pkg.tar.xz ] && _have_pkg=yes || _have_pkg=no
  echo $_have_pkg

  if [ "x$_have_pkg" == "xno" ]; then
    _pkgarch=$(pacman -Si $_pkgname | grep '^Architecture' | awk '{print $3}')

    # set arch to $CARCH, unless it is any
    [ "x$_pkgarch" == "xany" ] || _pkgarch=$CARCH

    msg "makepkg: $_pkgname"

    rm -rf "$_makepkgdir"/$_pkgname-decross
    mkdir -p "$_makepkgdir"/$_pkgname-decross
    pushd "$_makepkgdir"/$_pkgname-decross >/dev/null

    _pkgdir="$_makepkgdir"/$_pkgname-decross/pkg/$_pkgname

    fetch_pkgfiles $_pkgname
    import_keys

    cp PKGBUILD{,.old}
    patch -Np1 -i "$_srcdir"/patches/$_pkgname-decross.patch
    cp PKGBUILD{,.in}

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
    chown -R $SUDO_USER "$_makepkgdir"/$_pkgname-decross
    PKGDEST=. libremakepkg -n $CHOST-stage3 || failed_build

    notify -c success -u low "*decross* $_pkgname"

    popd >/dev/null
  fi

  # install the package
  set +o pipefail
  yes | librechroot \
      -n "$CHOST-stage3" \
      -C "$_builddir"/config/pacman.conf \
      -M "$_builddir"/config/makepkg.conf \
    install-file "$_makepkgdir"/$_pkgname-decross/$_pkgname-*.pkg.tar.xz
  set -o pipefail

  # remove pkg from deptree
  sed -i "/^$_pkgname-decross :/d; s/ $_pkgname\b//g" "$_deptree"
done
