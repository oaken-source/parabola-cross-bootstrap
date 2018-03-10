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

msg "preparing transitive dependency tree for $_groups (Stage 3)"

echo -n "checking for complete deptree ... "
[ -f "$_deptree".FULL ] && _have_deptree=yes || _have_deptree=no
echo $_have_deptree

if [ "x$_have_deptree" == "xno" ]; then
  declare -A _tree
  _frontier=($(pacman -Sg $_groups | awk '{print $2}'))

  while [ ${#_frontier[@]} -gt 0 ]; do
    # pop pkg from frontier
    _pkgname=$(echo ${_frontier[0]})
    _frontier=("${_frontier[@]:1}")

    # if seen before, skip, otherwise create entry in dependency tree
    [[ -v _tree[$_pkgname] ]] && continue
    _tree[$_pkgname]=""

    echo -en "\r  pkges: ${#_tree[@]} "

    _pkgdeps=$(pacman -Si $_pkgname | grep '^Depends' | cut -d':' -f2 | sed 's/None//')

    # add some additional build-time dependencies
    _extra_deps=""
    case $_pkgname in
      binutils)
        _extra_deps="git dejagnu bc" ;;
      gcc-libs)
        _extra_deps="dejagnu libmpc mpfr gmp" ;;
      libatomic_ops)
        _extra_deps="git" ;;
      libffi)
        _extra_deps="dejagnu git" ;;
      libpsl)
        _extra_deps="libxslt" ;;
      libtool)
        _extra_deps="git" ;;
      libseccomp)
        _extra_deps="git" ;;
      libxml2)
        _extra_deps="git python python2" ;;
      lz4)
        _extra_deps="git" ;;
      nss-*|libudev|libsystemd*)
        _extra_deps="libutil-linux pcre2 git meson" ;;
      patch)
        _extra_deps="ed" ;;
    esac

    # iterate dependencies for pkg
    for _dep in $_pkgdeps $_extra_deps; do
      # translate dependency string to actual package
      realdep=$(pacman --noconfirm -Sddw "$_dep" | grep '^Packages' | awk '{print $3}')
      realdep=${realdep%-*-*}
      # add dependency to tree and frontier
      _tree[$_pkgname]="${_tree[$_pkgname]} $realdep"
      _frontier+=($realdep)
    done
  done

  # following is a bit of magic to untangle the build dependencies
  for i in "${!_tree[@]}"; do
    _tree[$i]="${_tree[$i]/bash}"
  done
  _tree[gmp]="${_tree[gmp]/gcc-libs}"

  # write package dependency tree
  truncate -s0 "$_deptree".FULL
  for i in "${!_tree[@]}"; do
    echo "${i} : [${_tree[$i]} ]" >> "$_deptree".FULL
  done
fi

[ -f "$_deptree" ] || cp "$_deptree"{.FULL,}
chown $SUDO_USER "$_deptree"

echo "  total pkges:      $(cat "$_deptree".FULL | wc -l)"
echo "  remaining pkges:  $(cat "$_deptree" | wc -l)"
