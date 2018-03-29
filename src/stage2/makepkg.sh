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

check_makepkg() {
  echo -n "checking for makepkg-$CARCH.sh ... "

  local have_makepkg=yes
  [ -f "$BUILDDIR"/makepkg-"$CARCH".sh ] || have_makepkg=no
  echo $have_makepkg

  [ "x$have_makepkg" == "xyes" ] || return "$ERROR_MISSING"
}

build_makepkg() {
  check_exe bsdtar pacman || return

  prepare_makepkgdir "$MAKEPKGDIR/makepkg-$CARCH" || return

  # fetch pacman package to excract makepkg
  pacman -Sw --noconfirm --cachedir . pacman
  mkdir tmp && bsdtar -C tmp -xf pacman-*.pkg.tar.xz

  # install makepkg
  cp -Lv tmp/usr/bin/makepkg "$BUILDDIR"/makepkg-"$CARCH".sh

  # patch run_pacman in makepkg, we cannot pass the pacman root to it as parameter ATM
  sed -i "s#\"\$PACMAN_PATH\"#& --config $CHROOTDIR/etc/pacman.conf -r $CHROOTDIR#" \
    "$BUILDDIR"/makepkg-"$CARCH".sh

  popd >/dev/null || return
}

prepare_makepkg() {
  check_makepkg || build_makepkg || return

  # create a sane makepkg.conf
  cat "$SRCDIR"/makepkg.conf.in > "$BUILDDIR"/makepkg-"$CARCH".conf
  cat >> "$BUILDDIR"/makepkg-"$CARCH".conf << EOF
CARCH="$CARCH"
CHOST="$CHOST"
CFLAGS="-march=$GCC_MARCH -mabi=$GCC_MABI -O2 -pipe -fstack-protector-strong -fno-plt"
CXXFLAGS="-march=$GCC_MARCH -mabi=$GCC_MABI -O2 -pipe -fstack-protector-strong -fno-plt"
LOGDEST="$LOGDEST"
PKGDEST="$PKGDEST"
SRCDEST="$SRCDEST"
MAKEFLAGS="-j$(($(nproc) + 1))"
EOF

  check_repo "$PKGDEST" cross || make_repo "$PKGDEST" cross
}
