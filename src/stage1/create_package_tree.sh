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

msg "creating transitive dependency tree for $_groups"

declare -A _tree

_frontier=($(pacman -Sg $_groups | cut -d' ' -f2))
while [ ${#_frontier[@]} -gt 0 ]; do
  # pop pkg from frontier
  _pkg=$(echo ${_frontier[0]})
  _frontier=("${_frontier[@]:1}")
  # if seen before, skip, otherwise create entry in dependency tree
  [[ -v _tree[$_pkg] ]] && continue
  _tree[$_pkg]=""
  # iterate dependencies for pkg
  _deps="$(echo $(pacman -Si $_pkg | grep '^Depends' | cut -d':' -f2 | sed 's/None//'))"
  for dep in $_deps; do
    # translate dependency string to actual package
    realdep=$(yes n | pacman --confirm -Sd "$dep" 2>&1 | grep '^Packages' \
              | cut -d' ' -f3 | rev | cut -d'-' -f3- | rev)
    # add dependency to tree and frontier
    _tree[$_pkg]="${_tree[$_pkg]} $realdep"
    _frontier+=($realdep)
  done
done

# log package dependency tree
_deptree="$_builddir"/DEPTREE
echo "" > "$_deptree"
for i in "${!_tree[@]}"; do
  echo "  ${i} : [${_tree[$i]} ]" >> "$_deptree"
done
echo "total pkges: ${#_tree[@]}"

