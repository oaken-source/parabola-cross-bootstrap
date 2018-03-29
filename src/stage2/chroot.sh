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

check_chroot() {
  echo -n "checking for functional $CARCH skeleton chroot ... "

  local pacman_works=yes
  pacman --config "$CHROOTDIR"/etc/pacman.conf -r "$CHROOTDIR" -Syyu &>/dev/null || pacman_works=no
  echo $pacman_works

  [ "x$pacman_works" == "xyes" ] || return "$ERROR_MISSING"
}

build_chroot() {
  # create directories
  rm -rf "$CHROOTDIR"
  mkdir -pv "$CHROOTDIR"/etc/pacman.d/{gnupg,hooks} \
            "$CHROOTDIR"/var/{lib/pacman,cache/pacman/pkg,log} \
    | sed "s#$CHROOTDIR#\$CHROOTDIR#"

  # create sane pacman config
  cat > "$CHROOTDIR"/etc/pacman.conf << EOF
[options]
RootDir = $CHROOTDIR
DBPath = $CHROOTDIR/var/cache/pacman/
CacheDir = $CHROOTDIR/var/cache/pacman/pkg/
LogFile = $CHROOTDIR/var/log/pacman.log
GPGDir = $CHROOTDIR/etc/pacman.d/gnupg
HookDir = $CHROOTDIR/etc/pacman.d/hooks
Architecture = $CARCH

[cross]
SigLevel = Never
Server = file://${PKGDEST%/$CARCH}/\$arch
EOF

  # copy toolchain sysroot to chroot
  cp -ar "$SYSROOT"/usr "$CHROOTDIR"/

  # final sanity check
  check_chroot || return
}

umount_chrootdir() {
  umount "$SYSROOT"/usr

  trap - INT TERM EXIT
}

mount_chrootdir() {
  if mount | grep -q "$SYSROOT/usr"; then umount_chrootdir; fi
  mount -o bind "$CHROOTDIR"/usr "$SYSROOT"/usr

  trap 'umount_chrootdir' INT TERM EXIT
}

prepare_chroot() {
  check_chroot || build_chroot || return

  mount_chrootdir
}
