#!/bin/bash
 ##############################################################################
 #                      parabola-riscv64-bootstrap                            #
 #                                                                            #
 #    Copyright (C) 2018  Andreas Grapentin                                   #
 #    Copyright (C) 2018  Bruno Cichoń                                        #
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

startdir="$(pwd)"
export TOPSRCDIR="$startdir"/src
export CONFIGDIR="$startdir"/config

# shellcheck source=src/shared/common.sh
. "$TOPSRCDIR"/shared/common.sh

# sanity checks
if [ -z "$1" ]; then
  die -e "$ERROR_INVOCATION" "usage: $0 CARCH (see config/config.*.sh)"
fi
if [ "$(id -u)" -ne 0 ]; then
  die -e "$ERROR_INVOCATION" "must be root"
fi
if [ -z "${SUDO_USER:-}" ]; then
  die -e "$ERROR_INVOCATION" "SUDO_USER must be set in environment"
fi

# shellcheck source=config/config.template.sh
. "$CONFIGDIR/config.$1.sh" || die -e "$ERROR_INVOCATION" \
    "usage: $0 CARCH (see config/config.*.sh)"

mkdir -p "$TOPBUILDDIR" "$SRCDEST"
chown "$SUDO_USER" "$TOPBUILDDIR"

# shellcheck source=src/stage1/stage1.sh
. "$TOPSRCDIR"/stage1/stage1.sh
stage1 || die -e "$ERROR_BUILDFAIL" "Stage 1 failed. Exiting..."

# shellcheck source=src/stage2/stage2.sh
. "$TOPSRCDIR"/stage2/stage2.sh
stage2 || die -e "$ERROR_BUILDFAIL" "Stage 2 failed. Exiting..."

# shellcheck source=src/stage3/stage3.sh
. "$TOPSRCDIR"/stage3/stage3.sh
stage3 || die -e "$ERROR_BUILDFAIL" "Stage 3 failed. Exiting..."

# shellcheck source=src/stage4/stage4.sh
. "$TOPSRCDIR"/stage4/stage4.sh
stage4 || die -e "$ERROR_BUILDFAIL" "Stage 4 failed. Exiting..."

msg -n "all done."
