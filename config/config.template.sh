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

# the target host triplet
export CARCH=
export CHOST="$CARCH-unknown-linux-gnu"

# the equivalent architecture name used by the linux kernel
export LINUX_ARCH=

# flags added to the default CFLAGS in makepkg.conf
export PLATFORM_CFLAGS=()

# flags added to the gcc PKGBUILD configure call
export GCC_CONFIG_FLAGS=()

# multilib configuration, uncomment if applicable
#export MULTILIB=enable
#export CARCH32=""
#export CHOST32=""
#export PLATFORM32_CFLAGS=()

# configure build directories
export TOPBUILDDIR="$startdir/build/$CHOST"
export SRCDEST="$startdir"/build/sources

# regenerate config.sub / config.guess during builds
export REGEN_CONFIG_FRAGMENTS=yes

