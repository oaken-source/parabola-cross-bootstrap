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

msg "preparing $CARCH librechroot"

# create directories
mkdir -p "$_pkgdest" "$_logdest"

# initialize [native] repo
echo -n "checking for $CARCH [native] repo ... "
[ -e "$_pkgdest"/native.db ] && _have_native=yes || _have_native=no
echo $_have_native

if [ "x$_have_native" == "xno" ]; then
  tar -czf "$_pkgdest"/native.db.tar.gz -T /dev/null
  tar -czf "$_pkgdest"/native.files.tar.gz -T /dev/null
  ln -s native.db.tar.gz "$_pkgdest"/native.db
  ln -s native.files.tar.gz "$_pkgdest"/native.files
fi

# create configurations
mkdir -p "$_builddir"/config

cat > "$_builddir"/config/pacman.conf << EOF
[options]
Architecture = $CARCH
[native]
Server = file://$topbuilddir/stage3/packages/\$arch
[cross]
Server = file://$topbuilddir/stage2/packages/\$arch
EOF

cat "$_srcdir"/makepkg.conf.in > "$_builddir"/config/makepkg.conf
cat >> "$_builddir"/config/makepkg.conf << EOF
CARCH="$CARCH"
CHOST="$CHOST"
CFLAGS="-march=$GCC_MARCH -mabi=$GCC_MABI -O2 -pipe -fstack-protector-strong -fno-plt"
CXXFLAGS="-march=$GCC_MARCH -mabi=$GCC_MABI -O2 -pipe -fstack-protector-strong -fno-plt"
MAKEFLAGS="-j$(($(nproc) + 1))"
EOF

# initialize the chroot using the cross-compiled packages
rm -rf /var/cache/pacman/pkg-$CARCH/*
librechroot \
    -n "$CHOST-stage3" \
    -C "$_builddir"/config/pacman.conf \
    -M "$_builddir"/config/makepkg.conf \
  make

set +o pipefail
export _chrootdir="$(librechroot -n "$CHOST-stage3" 2>&1 | grep copydir.*: | awk '{print $3}')"
set -o pipefail

for repo in native cross; do
  mkdir -p "$_chrootdir"/$repo/$CARCH
  if mount | grep -q "$_chrootdir"/$repo/$CARCH; then umount "$_chrootdir"/$repo/$CARCH; fi
done
mount -o bind "$_pkgdest" "$_chrootdir"/native/$CARCH
mount -o bind "${_pkgdest//stage3/stage2}" "$_chrootdir"/cross/$CARCH

cat > "$_builddir"/config/pacman.conf << EOF
[options]
Architecture = $CARCH
[native]
Server = file:///native/\$arch
[cross]
Server = file:///cross/\$arch
EOF

librechroot \
    -n "$CHOST-stage3" \
    -C "$_builddir"/config/pacman.conf \
    -M "$_builddir"/config/makepkg.conf \
  update
