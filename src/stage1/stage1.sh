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

check_cross_toolchain() {
  echo -n "checking for $CHOST binutils ... "
  local have_binutils=yes
  type -p "$CHOST-ar" >/dev/null || have_binutils=no
  echo $have_binutils
  [ "x$have_binutils" == "xyes" ] || return 1

  echo -n "checking for $CHOST gcc ... "
  local have_gcc=yes
  type -p "$CHOST-g++" >/dev/null || have_gcc=no
  echo $have_gcc
  [ "x$have_gcc" == "xyes" ] || return 1

  local sysroot
  sysroot=$("$CHOST-gcc" --print-sysroot) || die "failed to produce $CHOST-gcc sysroot"

  echo -n "checking for $CHOST linux api headers ... "
  local have_headers=yes
  [ -e "$sysroot"/include/linux/kernel.h ] || have_headers=no
  echo $have_headers
  [ "x$have_headers" == "xyes" ] || return 1

  echo -n "checking for $CHOST glibc ... "
  local have_glibc=yes
  [ -e "$sysroot"/usr/lib/libc.so.6 ] || have_glibc=no
  echo $have_glibc
  [ "x$have_glibc" == "xyes" ] || return 1
}

stage1() {
  msg -n "Entering Stage 1"

  export BUILDDIR="$TOPBUILDDIR"/stage1
  export SRCDIR="$TOPSRCDIR"/stage1
  export PKGDEST="$BUILDDIR"/packages
  export LOGDEST="$BUILDDIR"/makepkglogs
  export MAKEPKGDIR="$BUILDDIR"

  check_cross_toolchain && return

  check_exe gpg makepkg pacman sed sudo || return

  # create required directories
  mkdir -p "$LOGDEST" "$PKGDEST" "$SRCDEST"
  chown "$SUDO_USER" "$LOGDEST" "$PKGDEST" "$SRCDEST"

  # create a sane makepkg.conf
  cat "$SRCDIR"/makepkg.conf.in > "$BUILDDIR"/makepkg.conf
  cat >> "$BUILDDIR"/makepkg.conf << EOF
LOGDEST="$LOGDEST"
PKGDEST="$PKGDEST"
SRCDEST="$SRCDEST"
MAKEFLAGS="-j$(($(nproc) + 1))"
EOF

  # build and install the toolchain packages
  for pkg in binutils linux-libre-api-headers gcc-bootstrap glibc gcc; do
    msg "makepkg: $CHOST-$pkg"

    if ! check_pkgfile "$PKGDEST" "$CHOST-$pkg"; then
      prepare_makepkgdir "$MAKEPKGDIR/$CHOST-$pkg" || return

      # produce pkgfiles
      for f in "$SRCDIR"/toolchain-pkgbuilds/$pkg/*.in; do cp "$f" "$(basename "${f%.in}")"; done
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

      import_keys || return

      if ! sudo -u "$SUDO_USER" makepkg -LC --config "$BUILDDIR"/makepkg.conf; then
        local log phase
        log=$(find_lastlog "$LOGDEST" "$CHOST-$pkg")
        if [ -z "$log" ]; then
          error -n "$CHOST-$pkg: error in makepkg"
        else
          phase=$(sed 's/.*\(pkgver\|prepare\|build\|package\).*/\1/' <<< "$log")
          error -n -d "$log" "$CHOST-$pkg: error in $phase"
        fi
        return "$ERROR_BUILDFAIL"
      fi

      popd >/dev/null || return
      notify -c success -u low "$CHOST-$pkg"
    fi

    # install the package
    # shellcheck disable=SC2010
    pkgfile=$(ls -t "$PKGDEST" | grep -P "^$CHOST-$pkg(-[^-]*){3}\\.pkg" | head -n1)
    yes | pacman -U "$PKGDEST/$pkgfile"
  done

  # final sanity check
  check_cross_toolchain || die -e "$ERROR_MISSING" "toolchain build incomplete"
}
