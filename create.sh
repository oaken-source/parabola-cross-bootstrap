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

# target options
export CARCH=riscv64
export CHOST=riscv64-linux-gnu
export LINUX_ARCH=riscv
export GCC_MARCH=rv64gc
export GCC_MABI=lp64d
# no riscv32 support as of glibc-2.27
#export MULTILIB=enable
#export GCC_32_MARCH=rv32gc
#export GCC_32_MABI=ilp32d
#export CARCH32=riscv32
#export CHOST32=riscv32-linux-gnu

# common directories
export startdir="$(pwd)"
export topbuilddir="$startdir"/build
export topsrcdir="$startdir"/src

# output control
. src/feedback.sh

[ $(id -u) -ne 0 ] && die "must be root"
[ -z "${SUDO_USER:-}" ] && die "SUDO_USER must be set in environment"

mkdir -p "$topbuilddir"
chown $SUDO_USER "$topbuilddir"

# Stage 1: prepare cross toolchain
./src/stage1/stage1.sh

# Stage 2: cross-compile base-devel
./src/stage2/stage2.sh

# Stage 3: libremakepkg native base-devel
./src/stage3/stage3.sh

msg "all done."
