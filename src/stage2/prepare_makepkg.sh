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

msg "preparing a $CARCH cross makepkg environment"

echo -n "checking for makepkg-$CARCH.sh ... "
[ -f "$_builddir"/makepkg-$CARCH.sh ] && _have_makepkg=yes || _have_makepkg=no
echo $_have_makepkg

if [ "x$_have_makepkg" == "xno" ]; then
  rm -rf "$_makepkgdir"/makepkg-$CARCH
  mkdir -p "$_makepkgdir"/makepkg-$CARCH
  pushd "$_makepkgdir"/makepkg-$CARCH >/dev/null

  # fetch pacman package to excract makepkg
  pacman -Sw --noconfirm --cachedir . pacman
  mkdir tmp && bsdtar -C tmp -xf pacman-*.pkg.tar.xz

  # install makepkg
  cp -Lv tmp/usr/bin/makepkg "$_builddir"/makepkg-$CARCH.sh

  # patch run_pacman in makepkg, we cannot pass the pacman root to it as parameter ATM
  sed -i "s#\"\$PACMAN_PATH\"#& --config $_chrootdir/etc/pacman.conf -r $_chrootdir#" \
    "$_builddir"/makepkg-$CARCH.sh
  popd >/dev/null
fi

# create a sane makepkg.conf
cat "$_srcdir"/makepkg.conf.in > "$_builddir"/makepkg-$CARCH.conf
cat >> "$_builddir"/makepkg-$CARCH.conf << EOF
CARCH="$CARCH"
CHOST="$CHOST"
CFLAGS="-march=$GCC_MARCH -mabi=$GCC_MABI -O2 -pipe -fstack-protector-strong -fno-plt"
CXXFLAGS="-march=$GCC_MARCH -mabi=$GCC_MABI -O2 -pipe -fstack-protector-strong -fno-plt"
PKGDEST="$_pkgdest"
LOGDEST="$_logdest"
MAKEFLAGS="-j$(($(nproc) + 1))"
EOF

_srcdest="$(source /etc/makepkg.conf && echo $SRCDEST || true)"
[ -z "$_srcdest" ] || echo "SRCDEST=\"$_srcdest\"" >> "$_builddir"/makepkg-$CARCH.conf

# create build artefact directories
mkdir -p "$_logdest" "$_pkgdest"
chown $SUDO_USER "$_logdest" "$_pkgdest"

# initialize [cross] repo
echo -n "checking for $CARCH [cross] repo ... "
[ -e "$_pkgdest"/cross.db ] && _have_cross=yes || _have_cross=no
echo $_have_cross

if [ "x$_have_cross" == "xno" ]; then
  tar -czf "$_pkgdest"/cross.db.tar.gz -T /dev/null
  tar -czf "$_pkgdest"/cross.files.tar.gz -T /dev/null
  ln -s cross.db.tar.gz "$_pkgdest"/cross.db
  ln -s cross.files.tar.gz "$_pkgdest"/cross.files
fi
