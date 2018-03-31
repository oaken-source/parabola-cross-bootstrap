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

prepare_stage4_makepkg() {
  mkdir -p "$BUILDDIR"/config

  cat > "$BUILDDIR"/config/pacman-bootstrap.conf << EOF
[options]
Architecture = $CARCH
[libre]
Server = file://$TOPBUILDDIR/stage4/packages/\$repo/os/\$arch
[core]
Server = file://$TOPBUILDDIR/stage4/packages/\$repo/os/\$arch
[extra]
Server = file://$TOPBUILDDIR/stage4/packages/\$repo/os/\$arch
[community]
Server = file://$TOPBUILDDIR/stage4/packages/\$repo/os/\$arch
[native]
Server = file://$TOPBUILDDIR/stage3/packages/\$arch
EOF

  cat > "$BUILDDIR"/config/pacman.conf << EOF
[options]
Architecture = $CARCH
[libre]
Server = file:///repos/\$repo/os/\$arch
[core]
Server = file:///repos/\$repo/os/\$arch
[extra]
Server = file:///repos/\$repo/os/\$arch
[community]
Server = file:///repos/\$repo/os/\$arch
[native]
Server = file:///native/\$arch
EOF

  cat >> "$BUILDDIR"/config/makepkg.conf << EOF
CARCH="$CARCH"
CHOST="$CHOST"
CFLAGS="-march=$GCC_MARCH -mabi=$GCC_MABI -O2 -pipe -fstack-protector-strong -fno-plt"
CXXFLAGS="-march=$GCC_MARCH -mabi=$GCC_MABI -O2 -pipe -fstack-protector-strong -fno-plt"
MAKEFLAGS="-j$(($(nproc) + 1))"
EOF

  local repo
  for repo in libre core extra community; do
    local repodir="$PKGDEST/../$repo/os/$CARCH"
    check_repo "$repodir" "$repo" || make_repo "$repodir" "$repo"
  done

  # patch libremakepkg to update config.sub/config.guess
  cat "$(which libremakepkg)" > "$BUILDDIR/libremakepkg-$CARCH.sh"
  chmod +x "$BUILDDIR/libremakepkg-$CARCH.sh"

  if [ "x${REGEN_CONFIG_FRAGMENTS:-no}" == "xyes" ]; then
	  local url="https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain"
    sed -i "/Boring\\/mundane/i \\
update_config_fragments() {\\
	find \$1/build -iname config.sub -exec curl \"$url;f=config.sub;hb=HEAD\" -o {} \\\\;\\
	find \$1/build -iname config.guess -exec curl \"$url;f=config.guess;hb=HEAD\" -o {} \\\\;\\
}\\
hook_pre_build+=(update_config_fragments)" "$BUILDDIR/libremakepkg-$CARCH.sh"
  fi

  # patch libremakepkg to disable checks
  sed -i 's/makepkg_args=(.*noconfirm[^)]*/& --nocheck/' "$BUILDDIR/libremakepkg-$CARCH.sh"
}
