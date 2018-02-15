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

_pkgname=ca-certificates-utils-shim
_pkgdir="$_makepkgdir"/$_pkgname/pkg/$_pkgname

msg "makepkg: $_pkgname"

if [ ! -h "$_makepkgdir"/$_pkgname.pkg.tar.xz ]; then
  rm -rf "$_makepkgdir"/$_pkgname
  mkdir -pv "$_makepkgdir"/$_pkgname
  pushd "$_makepkgdir"/$_pkgname >/dev/null

  _pkgver=$(pacman -Qi ${_pkgname%-*} | grep '^Version' | awk '{print $3}')

  # get original package
  pacman -Sw --noconfirm --cachedir . ${_pkgname%-*}
  mkdir tmp && bsdtar -C tmp -xf ${_pkgname%-*}-$_pkgver-*.pkg.tar.xz

  # install certificates
  mkdir -p "$_pkgdir"/etc/ssl/certs/
  cp -a tmp/etc/ssl/certs/ca-certificates.crt "$_pkgdir"/etc/ssl/certs/.

  # produce .PKGINFO file
  cat > "$_pkgdir"/.PKGINFO << EOF
pkgname = $_pkgname
pkgver = $_pkgver
pkgdesc = Common CA certificates (utilities) - extracted from host machine
url = http://pkgs.fedoraproject.org/cgit/rpms/ca-certificates.git
builddate = $(date '+%s')
size = 0
arch = $_arch
provide = ${_pkgname%-*}
conflict = ${_pkgname%-*}
EOF

  # package
  cd "$_pkgdir"
  env LANG=C bsdtar -czf .MTREE \
    --format=mtree \
    --options='!all,use-set,type,uid,gid,mode,time,size,md5,sha256,link' \
    .PKGINFO *
  env LANG=C bsdtar -cf - .MTREE .PKGINFO * | xz -c -z - > \
    "$_makepkgdir"/$_pkgname/$_pkgname-$_pkgver-$_arch.pkg.tar.xz

  ln -s "$_makepkgdir"/$_pkgname/$_pkgname-$_pkgver-$_arch.pkg.tar.xz \
    "$_makepkgdir"/$_pkgname.pkg.tar.xz

  popd >/dev/null
fi

cp -lv "$(readlink -f "$_makepkgdir"/$_pkgname.pkg.tar.xz)" "$_chrootdir"/packages/$_arch/

rm -rf "$_chrootdir"/var/cache/pacman/pkg/*
rm -rf "$_chrootdir"/packages/$_arch/repo.{db,files}*
repo-add -q -R "$_chrootdir"/packages/$_arch/{repo.db.tar.gz,*.pkg.tar.xz}
pacman --noscriptlet --noconfirm --config "$_chrootdir"/etc/pacman.conf \
  -r "$_chrootdir" -Syy $_pkgname

