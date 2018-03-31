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

check_stage3_chroot() {
  echo -n "checking for $CARCH chroot ... "

  local have_chroot=yes
  [ -e "$1" ] || have_chroot=no
  echo $have_chroot

  [ "x$have_chroot" == "xyes" ] || return "$ERROR_MISSING"
}

build_stage3_chroot() {
  rm -rf /var/cache/pacman/pkg-"$CARCH"/*
  librechroot -n "$CHOST-stage3" \
              -C "$BUILDDIR"/config/pacman-bootstrap.conf \
              -M "$BUILDDIR"/config/makepkg.conf \
    make || return
}

umount_stage3_chrootdir() {
  local chrootdir
  chrootdir="$(librechroot -n "$CHOST-stage3" 2>&1 | grep "copydir.*:" | awk '{print $3}')"

  umount "$chrootdir"/repos/native/"$CARCH"
  umount "$chrootdir"/repos/cross/"$CARCH"

  trap - INT TERM EXIT
}

mount_stage3_chrootdir() {
  mkdir -p "$1"/repos/{native,cross}/"$CARCH"
  for repo in native cross; do
    if mount | grep -q "$1/repos/$repo/$CARCH"; then umount "$1/repos/$repo/$CARCH"; fi
  done
  mount -o bind "$PKGDEST" "$1"/repos/native/"$CARCH"
  mount -o bind "${PKGDEST//stage3/stage2}" "$1"/repos/cross/"$CARCH"

  trap 'umount_stage3_chrootdir' INT TERM EXIT
}

prepare_stage3_chroot() {
  local chrootdir
  chrootdir="$(librechroot -n "$CHOST-stage3" 2>&1 | grep "copydir.*:" | awk '{print $3}')"

  check_stage3_chroot "$chrootdir" || build_stage3_chroot "$chrootdir" || return

  mount_stage3_chrootdir "$chrootdir"

  librechroot -n "$CHOST-stage3" \
              -C "$BUILDDIR"/config/pacman.conf \
              -M "$BUILDDIR"/config/makepkg.conf \
    update || return
}
