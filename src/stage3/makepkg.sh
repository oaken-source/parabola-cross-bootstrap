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

prepare_stage3_makepkg() {
  mkdir -p "$BUILDDIR"/config

  cat > "$BUILDDIR"/config/pacman-bootstrap.conf << EOF
[options]
Architecture = $CARCH
[native]
Server = file://$TOPBUILDDIR/stage3/packages/\$arch
[cross]
Server = file://$TOPBUILDDIR/stage2/packages/\$arch
EOF

  cat > "$BUILDDIR"/config/pacman.conf << EOF
[options]
Architecture = $CARCH
[native]
Server = file:///repos/native/\$arch
[cross]
Server = file:///repos/cross/\$arch
EOF

  cat "$SRCDIR"/makepkg.conf.in > "$BUILDDIR"/config/makepkg.conf
  cat >> "$BUILDDIR"/config/makepkg.conf << EOF
CARCH="$CARCH"
CHOST="$CHOST"
CFLAGS="${PLATFORM_CFLAGS[*]} -O2 -pipe -fstack-protector-strong -fno-plt"
CXXFLAGS="${PLATFORM_CFLAGS[*]} -O2 -pipe -fstack-protector-strong -fno-plt"
MAKEFLAGS="-j$(($(nproc) + 1))"
EOF

  check_repo "$PKGDEST" native || make_repo "$PKGDEST" native

  # patch libremakepkg to update config.sub/config.guess
  cat "$(command -v libremakepkg)" > "$BUILDDIR/libremakepkg.sh"
  chmod +x "$BUILDDIR/libremakepkg.sh"

  if [ "x${REGEN_CONFIG_FRAGMENTS:-no}" == "xyes" ]; then
	  local url="https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain"
    sed -i "/Boring\\/mundane/i \\
update_config_fragments() {\\
	find \$1/build -iname config.sub -exec curl \"$url;f=config.sub;hb=HEAD\" -o {} \\\\;\\
	find \$1/build -iname config.guess -exec curl \"$url;f=config.guess;hb=HEAD\" -o {} \\\\;\\
}\\
hook_pre_build+=(update_config_fragments)" "$BUILDDIR/libremakepkg.sh"
  fi

  # patch libremakepkg to disable checks
  sed -i 's/makepkg_args=(.*noconfirm[^)]*/& --nocheck/' "$BUILDDIR/libremakepkg.sh"
}
