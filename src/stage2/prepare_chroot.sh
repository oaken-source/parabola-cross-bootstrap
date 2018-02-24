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

msg "preparing a $CARCH skeleton chroot"

echo -n "checking for $CARCH skeleton chroot ... "
[ -e $_chrootdir ] && _have_chroot=yes || _have_chroot=no
echo $_have_chroot

if [ "x$_have_chroot" == "xno" ]; then
  # create required directories
  mkdir -pv "$_chrootdir"/etc/pacman.d/{gnupg,hooks} \
            "$_chrootdir"/var/{lib/pacman,cache/pacman/pkg,log} \
            "$_chrootdir"/packages/$CARCH \
    | sed "s#$_chrootdir#\$_chrootdir#"

  # create an empty local package directory
  tar -czf "$_chrootdir"/packages/$CARCH/repo.db.tar.gz -T /dev/null
  tar -czf "$_chrootdir"/packages/$CARCH/repo.files.tar.gz -T /dev/null
  ln -s repo.db.tar.gz "$_chrootdir"/packages/$CARCH/repo.db
  ln -s repo.files.tar.gz "$_chrootdir"/packages/$CARCH/repo.files

  # copy sysroot /usr to chroot
  cp -ar "$_sysroot"/usr "$_chrootdir"/

  # create pacman.conf
  cat > "$_chrootdir"/etc/pacman.conf << EOF
[options]
RootDir = $_chrootdir
DBPath = $_chrootdir/var/cache/pacman/
CacheDir = $_chrootdir/var/cache/pacman/pkg/
LogFile = $_chrootdir/var/log/pacman.log
GPGDir = $_chrootdir/etc/pacman.d/gnupg
HookDir = $_chrootdir/etc/pacman.d/hooks
Architecture = $CARCH

[repo]
SigLevel = Never
Server = file://${_pkgdest%/$CARCH}/\$arch
EOF

  # test and initialize ALPM library
  pacman --config "$_chrootdir"/etc/pacman.conf -r "$_chrootdir" -Syyu

  # make the package repository location writable to $SUDO_USER
  chown -R $SUDO_USER "$_chrootdir"/packages
fi

# mount chroot /usr to sysroot
if mount | grep -q "$_sysroot/usr"; then umount "$_sysroot"/usr; fi
mount -o bind "$_chrootdir"/usr "$_sysroot"/usr
