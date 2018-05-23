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

check_stage2_makepkg() {
  echo -n "checking for makepkg.sh ... "

  local have_stage2_makepkg=yes
  [ -f "$BUILDDIR"/makepkg.sh ] || have_stage2_makepkg=no
  echo $have_stage2_makepkg

  [ "x$have_stage2_makepkg" == "xyes" ] || return "$ERROR_MISSING"
}

build_stage2_makepkg() {
  check_exe bsdtar pacman || return

  prepare_makepkgdir "$MAKEPKGDIR/makepkg" || return

  # fetch pacman package to excract makepkg
  pacman -Sw --noconfirm --cachedir . pacman || return
  mkdir tmp && bsdtar -C tmp -xf pacman-*.pkg.tar.xz

  # install makepkg
  cp -Lv tmp/usr/bin/makepkg "$BUILDDIR"/makepkg.sh

  # patch run_pacman in makepkg, we cannot pass the pacman root to it as parameter ATM
  sed -i "s#\"\$PACMAN_PATH\"#& --config $CHROOTDIR/etc/pacman.conf -r $CHROOTDIR#" \
    "$BUILDDIR"/makepkg.sh

  popd >/dev/null || return
}

prepare_stage2_makepkg() {
  check_stage2_makepkg || build_stage2_makepkg || return

  # create a sane makepkg.conf
  cat "$SRCDIR"/makepkg.conf.in > "$BUILDDIR"/makepkg.conf
  cat >> "$BUILDDIR"/makepkg.conf << EOF
CARCH="$CARCH"
CHOST="$CHOST"
CFLAGS="${PLATFORM_CFLAGS[*]} -O2 -pipe -fstack-protector-strong -fno-plt"
CXXFLAGS="${PLATFORM_CFLAGS[*]} -O2 -pipe -fstack-protector-strong -fno-plt"
MAKEFLAGS="-j$(($(nproc) + 1))"
EOF

  check_repo "$PKGDEST" cross || make_repo "$PKGDEST" cross
}
