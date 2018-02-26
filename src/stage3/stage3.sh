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

msg "Entering Stage 3"

# set a bunch of convenience variables
_builddir="$topbuilddir"/stage3
_srcdir="$topsrcdir"/stage3
_chrootdir="$_builddir"/$CARCH-root
_deptree="$_builddir"/DEPTREE
_groups="base-devel"
_pkgdest="$_builddir"/packages
_logdest="$_builddir"/makepkglogs

check_exe librechroot
check_exe librelib
check_exe libremakepkg

# prepare for the build
. "$_srcdir"/prepare_libretools.sh

