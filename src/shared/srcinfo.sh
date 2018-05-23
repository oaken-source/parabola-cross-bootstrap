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

makesrcinfo() {
  if [ ! -f .SRCINFO ] || [ .SRCINFO -ot PKGBUILD ]; then
    (sudo -u "$SUDO_USER" makepkg --printsrcinfo) > .SRCINFO
  fi
}

srcinfo_validpgpkeys() {
  makesrcinfo
  grep 'validpgpkeys =' .SRCINFO | awk '{print $3}'
}

srcinfo_pkgbase() {
  makesrcinfo
  grep '^pkgbase =' .SRCINFO | awk '{print $3}'
}

srcinfo_pkgname() {
  $(basename $(pwd))
}

srcinfo_builddeps() {
  local OPTIND o n='check\|' m='make\|'
  while getopts "nm" o; do
    case "$o" in
      n) n='' ;;
      m) m='' ;;
      *) die -e "$ERROR_INVOCATION" "Usage: ${FUNCNAME[0]} [-n]" ;;
    esac
  done
  shift $((OPTIND-1))

  makesrcinfo
  awk '/^pkgbase = /,/^$/{print}' < .SRCINFO \
    | grep "	\\($m$n\\)depends =" | awk '{print $3}'
}

srcinfo_rundeps() {
  makesrcinfo
  awk '/^pkgname = '"$1"'$/,/^$/{print}' < .SRCINFO \
    | grep '	depends =' | awk '{print $3}'
}
