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

set -eu

# create base package tree
# . src/stage1/create_package_tree.sh

_chrootdir="$_builddir"/$_arch-root
_makepkgdir="$_builddir"/$_arch-makepkg

# prepare skeleton chroot
. src/stage1/create_chroot.sh

# prepare makepkg environment
. src/stage1/create_makepkg.sh

# create temporary shim packages
. src/stage1/shim-gcc-libs.sh
. src/stage1/shim-glibc.sh
. src/stage1/shim-ca-certificates-utils.sh
