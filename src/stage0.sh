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

check_bin() {
  echo -n "checking for $1 ... "
  type -p $1 >/dev/null && echo yes || (echo no && die "missing ${2:-$1} in \$PATH")
}

msg "performing host system sanity checks"

check_bin awk
check_bin bsdtar
check_bin gcc
check_bin makepkg
check_bin pacman
check_bin repo-add
check_bin sudo
check_bin tput
check_bin wget

check_bin help2man # for building libtool
check_bin tclsh    # for building sqlite

[ "x$_arch" != "x$(uname -m)" ] && check_bin $_target-gcc
[ "x$_arch" != "x$(uname -m)" ] && check_bin qemu-$_arch-static
