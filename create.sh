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

# target platform
export CARCH=riscv64
export CHOST=riscv64-unknown-linux-gnu
export LINUX_ARCH=riscv
export GCC_MARCH=rv64gc
export GCC_MABI=lp64d
#export MULTILIB=enable
#export GCC32_MARCH=rv32gc
#export GCC32_MABI=ilp32d
#export CARCH32=riscv32
#export CHOST32=riscv32-pc-linux-gnu

# common directories
startdir="$(pwd)"
export TOPBUILDDIR="$startdir"/build
export TOPSRCDIR="$startdir"/src
export SRCDEST="$TOPBUILDDIR"/sources
mkdir -p "$TOPBUILDDIR" "$SRCDEST"
chown "$SUDO_USER" "$TOPBUILDDIR"

# options
export KEEP_GOING=${KEEP_GOING:-no}
export REGEN_CONFIG_FRAGMENTS=${REGEN_CONFIG_FRAGMENTS:-yes}

# shellcheck source=src/shared/common.sh
. "$TOPSRCDIR"/shared/common.sh

# sanity checks
if [ "$(id -u)" -ne 0 ]; then
  die -e "$ERROR_INVOCATION" "must be root"
fi
if [ -z "${SUDO_USER:-}" ]; then
  die -e "$ERROR_INVOCATION" "SUDO_USER must be set in environment"
fi

# import stages
# shellcheck source=src/stage1/stage1.sh
. "$TOPSRCDIR"/stage1/stage1.sh
# shellcheck source=src/stage2/stage2.sh
. "$TOPSRCDIR"/stage2/stage2.sh
# shellcheck source=src/stage3/stage3.sh
. "$TOPSRCDIR"/stage3/stage3.sh
# shellcheck source=src/stage4/stage4.sh
. "$TOPSRCDIR"/stage4/stage4.sh

# run stages
stage1 || die -e "$ERROR_BUILDFAIL" "Stage 1 failed. Exiting..."
stage2 || die -e "$ERROR_BUILDFAIL" "Stage 2 failed. Exiting..."
stage3 || die -e "$ERROR_BUILDFAIL" "Stage 3 failed. Exiting..."
stage4 || die -e "$ERROR_BUILDFAIL" "Stage 4 failed. Exiting..."

msg -n "all done."
