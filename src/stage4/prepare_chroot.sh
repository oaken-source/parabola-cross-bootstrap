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

# initialize repos
mkdir -p "$_pkgdest"/{pool,staging}
for repo in libre core extra community; do
  echo -n "checking for $CARCH [$repo] repo ... "
  [ -e "$_pkgdest"/$repo/os/$CARCH/$repo.db ] && _have_repo=yes || _have_repo=no
  echo $_have_repo

  mkdir -p "$_pkgdest"/$repo/os/$CARCH
  if [ "x$_have_repo" == "xno" ]; then
    tar -czf "$_pkgdest"/$repo/os/$CARCH/$repo.db.tar.gz -T /dev/null
    tar -czf "$_pkgdest"/$repo/os/$CARCH/$repo.files.tar.gz -T /dev/null
    ln -s $repo.db.tar.gz "$_pkgdest"/$repo/os/$CARCH/$repo.db
    ln -s $repo.files.tar.gz "$_pkgdest"/$repo/os/$CARCH/$repo.files
  fi
done

# create configurations
mkdir -p "$_builddir"/config

cat > "$_builddir"/config/pacman.conf << EOF
[options]
Architecture = $CARCH
[libre]
Server = file://$topbuilddir/stage4/packages/\$repo/os/\$arch
[core]
Server = file://$topbuilddir/stage4/packages/\$repo/os/\$arch
[extra]
Server = file://$topbuilddir/stage4/packages/\$repo/os/\$arch
[community]
Server = file://$topbuilddir/stage4/packages/\$repo/os/\$arch
[native]
Server = file://$topbuilddir/stage3/packages/\$arch
EOF

cat "$_srcdir"/makepkg.conf.in > "$_builddir"/config/makepkg.conf
cat >> "$_builddir"/config/makepkg.conf << EOF
CARCH="$CARCH"
CHOST="$CHOST"
CFLAGS="-march=$GCC_MARCH -mabi=$GCC_MABI -O2 -pipe -fstack-protector-strong -fno-plt"
CXXFLAGS="-march=$GCC_MARCH -mabi=$GCC_MABI -O2 -pipe -fstack-protector-strong -fno-plt"
MAKEFLAGS="-j$(($(nproc) + 1))"
EOF

# initialize the chroot
rm -rf /var/cache/pacman/pkg-$CARCH/*
librechroot \
    -n "$CHOST-stage4" \
    -C "$_builddir"/config/pacman.conf \
    -M "$_builddir"/config/makepkg.conf \
  make

set +o pipefail
export _chrootdir="$(librechroot -n "$CHOST-stage4" 2>&1 | grep copydir.*: | awk '{print $3}')"
set -o pipefail

# mount repo in chroot
mkdir -p "$_chrootdir"/{repos,native}
if mount | grep -q "$_chrootdir"/repos; then umount "$_chrootdir"/repos; fi
if mount | grep -q "$_chrootdir"/native; then umount "$_chrootdir"/native; fi
mount -o bind "$topbuilddir/stage4/packages" "$_chrootdir"/repos
mount -o bind "$topbuilddir/stage3/packages" "$_chrootdir"/native

cat > "$_builddir"/config/pacman.conf << EOF
[options]
Architecture = $CARCH
[libre]
Server = file:///repos/\$repo/os/\$arch
[core]
Server = file:///repos/\$repo/os/\$arch
[extra]
Server = file:///repos/\$repo/os/\$arch
[community]
Server = file:///repos/\$repo/os/\$arch
[native]
Server = file:///native/\$arch
EOF

librechroot \
    -n "$CHOST-stage4" \
    -C "$_builddir"/config/pacman.conf \
    -M "$_builddir"/config/makepkg.conf \
  update

# produce a patched libremakepkg to update config.sub/config.guess where needed
cat $(which libremakepkg) > "$_builddir"/libremakepkg-$CARCH.sh
chmod +x "$_builddir"/libremakepkg-$CARCH.sh
if [ "x${REGEN_CONFIG_FRAGMENTS:-no}" == "xyes" ]; then
  sed -i '/Boring\/mundane/i \
update_config_fragments() {\
	local url="https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain"\
	find $1/build -iname config.sub -print -exec curl "$url;f=config.sub;hb=HEAD" -o {} \\;\
	find $1/build -iname config.guess -print -exec curl "$url;f=config.guess;hb=HEAD" -o {} \\;\
}\
hook_pre_build+=(update_config_fragments)' "$_builddir"/libremakepkg-$CARCH.sh
fi
