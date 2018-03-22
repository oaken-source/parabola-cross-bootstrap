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

msg "preparing transitive dependency tree for $_groups (Stage 4)"

echo -n "checking for complete deptree ... "
[ -f "$_deptree".FULL ] && _have_deptree=yes || _have_deptree=no
echo $_have_deptree

if [ "x$_have_deptree" == "xno" ]; then
  truncate -s0 "$_deptree".FULL

  for _group in $_groups; do
    for _pkg in $(pacman -Sg $_group | awk '{print $2}'); do
      _realpkg=$(pacman --noconfirm -Sddw "$_pkg" | grep '^Packages' | awk '{print $3}')
      _realpkg="${_realpkg%-*-*}"
      if ! grep -q "^$_realpkg :" "$_deptree".FULL; then
        echo "$_realpkg : [ ] # $_group" >> "$_deptree".FULL
      else
        sed -i "s/^$_realpkg : \[.*/&, $_group/" "$_deptree".FULL
      fi
    done
  done
fi

[ -f "$_deptree" ] || cp "$_deptree"{.FULL,}
chown $SUDO_USER "$_deptree"

echo "  total pkges:      $(cat "$_deptree".FULL | wc -l)"
echo "  remaining pkges:  $(cat "$_deptree" | wc -l)"
