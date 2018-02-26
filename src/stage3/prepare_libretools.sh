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

msg "preparing libretools for native $CARCH builds"

echo -n "checking for patched libretools ... "
[ -f "$_builddir"/librechroot-$CARCH.sh ] && _have_librechroot=yes || _have_librechroot=no
echo $_have_librechroot

if [ "x$_have_librechroot" == "xno" ]; then
  rm -rf "$_builddir"/libretools-$CARCH
  mkdir -p "$_builddir"/libretools-$CARCH
  pushd "$_builddir"/libretools-$CARCH >/dev/null

  # fetch libretools package to excract librechroot, libremakepkg
  pacman -Sw --noconfirm --cachedir . libretools
  mkdir tmp && bsdtar -C tmp -xf libretools-*.pkg.tar.xz
  cp -aR tmp old

  # patch tools
  patch -Np1 -d tmp/ -i "$_srcdir"/libretools.patch

  # override default config path
  sed -i "/librelib conf/i export XDG_CONFIG_HOME=$_builddir/config" \
    tmp/usr/bin/librechroot

  # create configurations
  mkdir -p "$_builddir"/config/libretools/
  cat > "$_builddir"/config/libretools/chroot.conf << EOF
CHROOTDIR="$_chrootdir"
EOF

  cat > "$_builddir"/config/pacman.conf << EOF
[options]
Architecture = $CARCH
[cross]
Server = file://$topbuilddir/stage2/$CARCH-root/packages/\$arch
EOF

  cat "$_srcdir"/makepkg.conf.in > "$_builddir"/config/makepkg.conf
  cat >> "$_builddir"/config/makepkg.conf << EOF
CARCH="$CARCH"
CHOST="$CHOST"
CFLAGS="-march=$GCC_MARCH -mabi=$GCC_MABI -O2 -pipe -fstack-protector-strong -fno-plt"
CXXFLAGS="-march=$GCC_MARCH -mabi=$GCC_MABI -O2 -pipe -fstack-protector-strong -fno-plt"
EOF

  # install librechroot
  cp -Lv tmp/usr/bin/librechroot "$_builddir"/librechroot-$CARCH.sh
  # install libremakepkg
  cp -Lv tmp/usr/bin/libremakepkg "$_builddir"/libremakepkg-$CARCH.sh

  popd >/dev/null
fi

echo -n "checking for $CARCH chroot ... "
[ -e "$_chrootdir"/default/root ] && _have_chroot=yes || _have_chroot=no
echo $_have_chroot

if [ "x$_have_chroot" == "xno" ]; then
  $_builddir/librechroot-$CARCH.sh \
      -C "$_builddir"/config/pacman.conf \
      -M "$_builddir"/config/makepkg.conf \
      -r "$_builddir"/../stage2/$CARCH-root/packages:/packages \
    make
fi
