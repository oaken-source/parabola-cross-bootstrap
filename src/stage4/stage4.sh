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

msg "Entering Stage 4"
notify "*Bootstrap Entering Stage 4*"

# set a bunch of convenience variables
_builddir="$topbuilddir"/stage4
_srcdir="$topsrcdir"/stage4
_makepkgdir="$_builddir"/$CARCH-makepkg
_deptree="$_builddir"/DEPTREE
_groups="base base-devel"
_pkgdest="$_builddir"/packages
_logdest="$_builddir"/makepkglogs

export PKGDEST="$_pkgdest/staging"
export LOGDEST="$_logdest"

check_exe librechroot
check_exe libremakepkg

# make sure that binfmt is *enabled* for stage4 build
echo 1 > /proc/sys/fs/binfmt_misc/status

# prepare for the build
. "$_srcdir"/prepare_chroot.sh
. "$_srcdir"/prepare_deptree.sh

msg "starting $CARCH native build (phase 2)"

# keep building packages until the deptree is empty
while [ -s "$_deptree" ]; do
  # grab one without unfulfilled dependencies
  _pkgname=$(grep '\[ *\]' "$_deptree" | head -n1 | awk '{print $1}') || true
  [ -n "$_pkgname" ] || die "could not resolve dependencies. exiting."

  msg "makepkg: $_pkgname"
  msg "  remaining packages: $(cat "$_deptree" | wc -l)"

  prepare_makepkgdir
  fetch_pkgfiles $_pkgname
  import_keys

  # produce pkgbase
  echo -n "checking for pkgbase ... "
  _srcinfo=$(sudo -u $SUDO_USER makepkg --config "$_builddir"/config/makepkg.conf --printsrcinfo)
  _pkgbase=$(echo "$_srcinfo" | grep '^pkgbase =' | awk '{print $3}')
  [ -n "$_pkgbase" ] || _pkgbase=$_pkgname
  echo "$_pkgbase"

  # patch if necessary
  cp PKGBUILD{,.old}
  [ -f "$_srcdir"/patches/$_pkgbase.patch ] && \
    patch -Np1 -i "$_srcdir"/patches/$_pkgbase.patch
  cp PKGBUILD{,.in}
  chown -R $SUDO_USER "$_makepkgdir"/$_pkgname

  # substitute common variables
  sed -i \
      "s#@MULTILIB@#${MULTILIB:-disable}#g" \
    PKGBUILD

  # enable the target CARCH in arch array, unless it is already 'any'
  sed -i "/arch=(.*\bany\b.*)/!s/arch=([^)]*/& $CARCH/" PKGBUILD

  # scan dependencies and update deptree
  set +o pipefail
  _needs_postpone=no
  _srcinfo=$(sudo -u $SUDO_USER makepkg --config "$_builddir"/config/makepkg.conf --printsrcinfo)
  _builddeps=$(echo "$_srcinfo" | awk '/^pkgbase = /,/^$/{print}' \
      | grep '	\(make\|check\|\)depends =' | awk '{print $3}')
  _rundeps=$(echo "$_srcinfo" | awk '/^pkgname = '$_pkgname'$/,/^$/{print}' \
      | grep '	depends =' | awk '{print $3}')
  # make sure all deps (build-time and run-time) are in deptree
  for _dep in $_builddeps $_rundeps; do
    _realdep=""
    make_realdep "$_dep"

    [ -n "$_realdep" ] || die "failed to translate dependency string '$_dep'"
    if ! grep -q "^$_realdep :" "$_deptree".FULL; then
      echo "$_realdep : [ ] # $_pkgname" >> "$_deptree".FULL
      echo "$_realdep : [ ] # $_pkgname" >> "$_deptree"
    else
      sed -i "/#.* $_pkgname\(\$\|[ ,]\)/! s/^$_realdep : \[.*/&, $_pkgname/" "$_deptree"{,.FULL}
    fi
  done
  # postpone build on missing build-time deps
  for _dep in $_builddeps; do
    _realdep=""
    make_realdep "$_dep"
    [ -n "$_realdep" ] || die "failed to translate dependency string '$_dep'"

    echo -n "checking for built dependency $_realdep ... "
    _depfile=$(find $_pkgdest/pool $topbuilddir/stage3/packages/ \
      -regex "^.*/$_realdep-[^-]*-[^-]*-[^-]*\.pkg\.tar\.xz\$")
    [ -n "$_depfile" ] && _have_dep=yes || _have_dep=no
    echo $_have_dep

    if [ "x$_have_dep" == "xno" ]; then
      sed -i "s/^$_pkgname : \[/& $_realdep/" "$_deptree"{,.FULL}
      _needs_postpone=yes
    fi
  done
  set -o pipefail

  # missing stuff - put back to deptree and try again.
  if [ "x$_needs_postpone" == "xyes" ]; then
    popd >/dev/null
    continue
  fi

  echo -n "checking for built $_pkgname package ... "
  _pkgfile=$(find $_pkgdest/pool -regex "^.*/$_pkgname-[^-]*-[^-]*-[^-]*\.pkg\.tar\.xz\$")
  [ -n "$_pkgfile" ] && _have_pkg=yes || _have_pkg=no
  echo $_have_pkg

  if [ "x$_have_pkg" == "xno" ]; then
    # clean staging
    rm -f "$_pkgdest"/staging/*

    # build the package
    "$_builddir"/libremakepkg-$CARCH.sh -n $CHOST-stage4 || failed_build

    # release the package
    _pkgrepo=$(cat .REPO)
    for f in "$_pkgdest"/staging/*; do
      ln -s ../../../pool/$(basename "$f") "$_pkgdest"/$_pkgrepo/os/$CARCH/$(basename "$f")
      mv $f "$_pkgdest"/pool/
    done

    rm -rf /var/cache/pacman/pkg-$CARCH/*
    rm -rf "$_pkgdest"/$_pkgrepo/os/$CARCH/$_pkgrepo.{db,files}*
    repo-add -q -R "$_pkgdest"/$_pkgrepo/os/$CARCH/{$_pkgrepo.db.tar.gz,*.pkg.tar.xz}

    # install in chroot
    _pkgfile=$(find $_pkgdest/pool -regex "^.*/$_pkgname-[^-]*-[^-]*-[^-]*\.pkg\.tar\.xz\$" \
      | head -n1)
    set +o pipefail
    yes | librechroot \
        -n "$CHOST-stage4" \
        -C "$_builddir"/config/pacman.conf \
        -M "$_builddir"/config/makepkg.conf \
      run pacman -Udd /repos/pool/"$(basename "$_pkgfile")"
    yes | librechroot \
        -n "$CHOST-stage4" \
        -C "$_builddir"/config/pacman.conf \
        -M "$_builddir"/config/makepkg.conf \
      run pacman -Syyuu
    set -o pipefail
  fi

  # remove pkg from deptree
  sed -i "/^$_pkgname :/d; s/ /  /g; s/ $_pkgname / /g; s/  */ /g" "$_deptree"

  full=$(cat "$_deptree".FULL | wc -l)
  curr=$(expr $full - $(cat "$_deptree" | wc -l))
  notify -c success -u low "*$curr/$full* $_pkgname"

  popd >/dev/null
done

# unmount
umount "$_chrootdir"/native
umount "$_chrootdir"/repos

echo "all packages built."
