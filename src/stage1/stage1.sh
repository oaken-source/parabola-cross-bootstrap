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

msg "Entering Stage 1"
notify "*Bootstrap Entering Stage 1*"

# set a bunch of convenience variables
_builddir="$topbuilddir"/stage1
_srcdir="$topsrcdir"/stage1
_pkgdest="$_builddir"/packages
_logdest="$_builddir"/makepkglogs
_makepkgdir="$_builddir"

function check_toolchain() {
  echo -n "checking for $CHOST binutils ... "
  local _have_binutils
  type -p $CHOST-ar >/dev/null && _have_binutils=yes || _have_binutils=no
  echo $_have_binutils
  [ "x$_have_binutils" == "xyes" ] || return 1

  echo -n "checking for $CHOST gcc ... "
  local _have_gcc
  type -p $CHOST-g++ >/dev/null && _have_gcc=yes || _have_gcc=no
  echo $_have_gcc
  [ "x$_have_gcc" == "xyes" ] || return 1

  local _sysroot=$($CHOST-gcc --print-sysroot)

  echo -n "checking for $CHOST linux api headers ... "
  local _have_headers
  [ -e "$_sysroot"/include/linux/kernel.h ] && _have_headers=yes || _have_headers=no
  echo $_have_headers
  [ "x$_have_headers" == "xyes" ] || return 1

  echo -n "checking for $CHOST glibc ... "
  local _have_glibc
  [ -e "$_sysroot"/usr/lib/libc.so.6 ] && _have_glibc=yes || _have_glibc=no
  echo $_have_glibc
  [ "x$_have_glibc" == "xyes" ] || return 1
}

# simply return if the toolchain is already there
if check_toolchain; then return 0; fi

# check for required programs in $PATH to build the toolchain
check_exe makepkg
check_exe pacman
check_exe sed
check_exe sudo

# create required directories
mkdir -p "$_logdest" "$_pkgdest"
chown $SUDO_USER "$_logdest" "$_pkgdest"

# create a sane makepkg.conf
cat "$_srcdir"/makepkg.conf.in > "$_builddir"/makepkg.conf
cat >> "$_builddir"/makepkg.conf << EOF
CARCH="$(source /etc/makepkg.conf && echo $CARCH)"
CHOST="$(source /etc/makepkg.conf && echo $CHOST)"
CPPFLAGS="$(source /etc/makepkg.conf && echo $CPPFLAGS)"
CFLAGS="$(source /etc/makepkg.conf && echo $CFLAGS)"
CXXFLAGS="$(source /etc/makepkg.conf && echo $CXXFLAGS)"
LDFLAGS="$(source /etc/makepkg.conf && echo $LDFLAGS)"
LOGDEST="$_logdest"
PKGDEST="$_pkgdest"
MAKEFLAGS="-j$(($(nproc) + 1))"
EOF

_srcdest="$(source /etc/makepkg.conf && echo $SRCDEST || true)"
[ -z "$_srcdest" ] || echo "SRCDEST=\"$_srcdest\"" >> "$_builddir"/makepkg.conf

# build and install the toolchain packages
for pkg in binutils linux-libre-api-headers gcc-bootstrap glibc gcc; do
  _pkgname=$CHOST-$pkg
  echo -n "checking for $_pkgname ... "
  _pkgfile=$(find $_pkgdest -regex "^.*/$_pkgname-[^-]*-[^-]*-[^-]*\.pkg\.tar\.xz\$")
  [ -n "$_pkgfile" ] && _have_pkg=yes || _have_pkg=no
  echo $_have_pkg

  if [ "x$_have_pkg" == "xno" ]; then
    msg "makepkg: $_pkgname"
    prepare_makepkgdir

    cp "$_srcdir"/toolchain-pkgbuilds/$pkg/PKGBUILD.in .

    import_keys

    # substitute architecture variables
    sed -i "s#@CHOST@#$CHOST#g; \
            s#@CARCH@#$CARCH#g; \
            s#@LINUX_ARCH@#$LINUX_ARCH#g; \
            s#@GCC_MARCH@#${GCC_MARCH:-}#g; \
            s#@GCC_MABI@#${GCC_MABI:-}#g; \
            s#@MULTILIB@#${MULTILIB:-disable}#g; \
            s#@GCC_32_MARCH@#${GCC_32_MARCH:-}#g; \
            s#@GCC_32_MABI@#${GCC_32_MABI:-}#g; \
            s#@CARCH32@#${CARCH32:-}#g; \
            s#@CHOST32@#${CHOST32:-}#g" \
      PKGBUILD

    # build the package
    chown -R $SUDO_USER .
    sudo -u $SUDO_USER makepkg -LC --config "$_builddir"/makepkg.conf || failed_build

    popd >/dev/null
    notify -c success -u low "$_pkgname"
  fi

  # install the package
  set +o pipefail
  _pkgfile=$(find $_pkgdest -regex "^.*/$_pkgname-[^-]*-[^-]*-[^-]*\.pkg\.tar\.xz\$" | head -n1)
  yes | pacman -U "$_pkgfile"
  set -o pipefail
done

# final sanity check
check_toolchain || die "toolchain build incomplete"
