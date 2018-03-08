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

msg "Entering Stage 3"
notify --text "*Bootstrap Entering Stage 3*"

# set a bunch of convenience variables
_builddir="$topbuilddir"/stage3
_srcdir="$topsrcdir"/stage3
_makepkgdir="$_builddir"/$CARCH-makepkg
_deptree="$_builddir"/DEPTREE
_groups="base-devel"
_pkgdest="$_builddir"/packages/$CARCH
_logdest="$_builddir"/makepkglogs

export PKGDEST="$_pkgdest"
export LOGDEST="$_logdest"

check_exe librechroot
check_exe libremakepkg
check_exe makepkg

# make sure that binfmt is *enabled* for stage2 build
echo 1 > /proc/sys/fs/binfmt_misc/status

# prepare for the build
. "$_srcdir"/prepare_chroot.sh
. "$_srcdir"/prepare_deptree.sh
. "$_srcdir"/prepare_decross.sh

msg "starting $CARCH native build"

# keep building packages until the deptree is empty
while [ -s "$_deptree" ]; do
  # grab one without unfulfilled dependencies
  _pkgname=$(grep '\[ *\]' "$_deptree" | head -n1 | awk '{print $1}') || true
  [ -n "$_pkgname" ] || die "could not resolve dependencies. exiting."

  _pkgarch=$(pacman -Si $_pkgname | grep '^Architecture' | awk '{print $3}')

  # set arch to $CARCH, unless it is any
  [ "x$_pkgarch" == "xany" ] || _pkgarch=$CARCH

  msg "makepkg: $_pkgname"
  msg "  remaining packages: $(cat "$_deptree" | wc -l)"

  echo -n "checking for built $_pkgname package ... "
  _pkgfile=$(find $_pkgdest -regex "^.*/$_pkgname-[^-]*-[^-]*-[^-]*\.pkg\.tar\.xz\$")
  [ -n "$_pkgfile" ] && _have_pkg=yes || _have_pkg=no
  echo $_have_pkg

  if [ "x$_have_pkg" == "xno" ]; then
    # prepare directories
    _pkgdir="$_makepkgdir"/$_pkgname/pkg/$_pkgname
    rm -rf "$_makepkgdir"/$_pkgname
    mkdir -pv "$_makepkgdir"/$_pkgname
    pushd "$_makepkgdir"/$_pkgname >/dev/null

    if [ "x$_pkgarch" == "xany" ]; then
      # repackage arch=(any) packages
      _pkgver=$(pacman -Si $_pkgname | grep '^Version' | awk '{print $3}')
      pacman -Sw --noconfirm --cachedir "$_pkgdest" $_pkgname
      ln -s "$_pkgdest"/$_pkgname-$_pkgver-any.pkg.tar.xz \
        "$_makepkgdir"/$_pkgname/$_pkgname-$_pkgver-any.pkg.tar.xz
    elif [ "x$_pkgname" == "xca-certificates-mozilla" ]; then
      # repackage ca-certificates-mozilla to avoid building nss
      _pkgver=$(pacman -Si $_pkgname | grep '^Version' | awk '{print $3}')
      pacman -Sw --noconfirm --cachedir . $_pkgname
      mkdir tmp && bsdtar -C tmp -xf $_pkgname-$_pkgver-*.pkg.tar.xz
      mkdir -p "$_pkgdir"/usr/share/
      cp -rv tmp/usr/share/ca-certificates/ "$_pkgdir"/usr/share/
      cat > "$_pkgdir"/.PKGINFO << EOF
pkgname = $_pkgname
pkgver = $_pkgver
pkgdesc = Mozilla's set of trusted CA certificates
url = https://developer.mozilla.org/en-US/docs/Mozilla/Projects/NSS
builddate = $(date '+%s')
size = 0
arch = $_pkgarch
EOF
      cd "$_pkgdir"
      env LANG=C bsdtar -czf .MTREE \
        --format=mtree \
        --options='!all,use-set,type,uid,gid,mode,time,size,md5,sha256,link' \
        .PKGINFO *
      env LANG=C bsdtar -cf - .MTREE .PKGINFO * | xz -c -z - > \
        "$_pkgdest"/$_pkgname-$_pkgver-$_pkgarch.pkg.tar.xz
      ln -s "$_pkgdest"/$_pkgname-$_pkgver-$_pkgarch.pkg.tar.xz \
        "$_makepkgdir"/$_pkgname/$_pkgname-$_pkgver-$_pkgarch.pkg.tar.xz
    else
      fetch_pkgfiles $_pkgname
      import_keys

      # patch if necessary
      cp PKGBUILD{,.old}
      [ -f "$_srcdir"/patches/$_pkgname.patch ] && \
        patch -Np1 -i "$_srcdir"/patches/$_pkgname.patch
      cp PKGBUILD{,.in}

      # substitute common variables
      _config="https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain"
      _config_sub="$_config;f=config.sub;hb=HEAD"
      _config_guess="$_config;f=config.guess;hb=HEAD"
      sed -i "s#@CONFIG_SUB@#curl \"$_config_sub\"#g; \
              s#@CONFIG_GUESS@#curl \"$_config_guess\"#g; \
              s#@MULTILIB@#${MULTILIB:-disable}#g" \
        PKGBUILD

      # enable the target CARCH in arch array
      sed -i "s/arch=([^)]*/& $CARCH/" PKGBUILD

      # build the package
      chown -R $SUDO_USER "$_makepkgdir"/$_pkgname
      libremakepkg -n $CHOST-stage3 || failed_build
    fi

    popd >/dev/null

    # update pacman cache
    rm -rf /var/cache/pacman/pkg-$CARCH/*
    rm -rf "$_pkgdest"/native.{db,files}*
    repo-add -q -R "$_pkgdest"/{native.db.tar.gz,*.pkg.tar.xz}
  fi

  # install in chroot
  _pkgfile=$(find $_pkgdest -regex "^.*/$_pkgname-[^-]*-[^-]*-[^-]*\.pkg\.tar\.xz\$" | head -n1)
  set +o pipefail
  yes | librechroot \
      -n "$CHOST-stage3" \
      -C "$_builddir"/config/pacman.conf \
      -M "$_builddir"/config/makepkg.conf \
    run pacman -Udd /native/$CARCH/"$(basename "$_pkgfile")"
  set -o pipefail

  # remove pkg from deptree
  sed -i "/^$_pkgname :/d; s/ $_pkgname\b//g" "$_deptree"

  full=$(cat "$_deptree".FULL | wc -l)
  curr=$(expr $full - $(cat "$_deptree" | wc -l))
  notify --success --text "*$curr/$full* $_pkgname"
done

# unmount
umount "$_chrootdir"/native/$CARCH

echo "all packages built."
