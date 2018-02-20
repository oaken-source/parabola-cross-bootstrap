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

. src/feedback.sh

[ $(id -u) -ne 0 ] && die "must be root"
[ -z "${SUDO_USER:-}" ] && die "SUDO_USER not set"

export _startdir="$(pwd)"
export _builddir="$_startdir"/build
export _srcdir="$_startdir"/src
export _target=riscv64-linux-gnu
export _arch=${_target%%-*}
export _linux_arch=riscv
export _groups="base base-devel"
#export _groups="base"

msg "preparing builddir"
mkdir -vp "$_builddir"
chown -v $SUDO_USER "$_builddir"

# stage 0: prepare host
./src/stage0.sh

export _buildhost=$(gcc -dumpmachine)
export _sysroot=$($_target-gcc --print-sysroot)

# stage 1: cross-makepkg a base system
./src/stage1.sh

# cleanup
# rm -rf "$_builddir"
echo "all done :)"
