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

msg "creating transitive dependency tree for $_groups"

if [ ! -f "$_deptree" ]; then
  declare -A _tree

  # remove a couple painful things from base we don't need for stage1
  _frontier=($(pacman -Sg $_groups | awk '{print $2}'))

  while [ ${#_frontier[@]} -gt 0 ]; do
    # pop pkg from frontier
    _pkgname=$(echo ${_frontier[0]})
    _frontier=("${_frontier[@]:1}")

    # if seen before, skip, otherwise create entry in dependency tree
    [[ -v _tree[$_pkgname] ]] && continue
    _tree[$_pkgname]=""

    _pkgdeps=$(pacman -Si $_pkgname | grep '^Depends' | cut -d':' -f2 | sed 's/None//')

    # iterate dependencies for pkg
    for dep in $_pkgdeps; do
      # translate dependency string to actual package
      realdep=$(pacman --noconfirm -Sw "$dep" | grep '^Packages' | awk '{print $3}')
      realdep=${realdep%-*-*}
      # add dependency to tree and frontier
      _tree[$_pkgname]="${_tree[$_pkgname]} $realdep"
      _frontier+=($realdep)
    done
  done

  # resolve gmp / gcc-libs cyclic dependency
  _tree[gcc-libs]="${_tree[gcc-libs]} libmpc mpfr gmp"
  _tree[gmp]="${_tree[gmp]/gcc-libs}"
  _tree[gmp]="${_tree[gmp]/bash}"
  # resolve systemd / util-linux dependency cycle
  _tree[libutil-linux]="${_tree[libutil-linux]/libsystemd}"
  _tree[util-linux]="${_tree[util-linux]/libsystemd}"

  # building libcap needs pam and unixodbc in sysroot
  _tree[libcap]="${_tree[libcap]} pam unixodbc"
  _tree[unixodbc]=" readline libtool"
  # building libpsl requires publicsuffix-list in sysroot
  _tree[libpsl]="${_tree[libpsl]} publicsuffix-list"
  _tree[publicsuffix-list]=""
  # building libutil-linux needs a bunch of stuff in sysroot
  _tree[libutil-linux]="${_tree[util-linux]/libutil-linux}"
  # building sqlite requires tcl in sysroot
  _tree[sqlite]="${_tree[sqlite]} tcl"
  _tree[tcl]=" zlib"
  # building iptables requires libnfnetlink and libnetfilter_conntrack in sysroot
  _tree[iptables]="${_tree[iptables]} libnfnetlink libnetfilter_conntrack "
  _tree[libnfnetlink]=" glibc"
  _tree[libnetfilter_conntrack]=" libnfnetlink libmnl"

  # we build stage1 without guile, gc, libsecret, libldap and krb5
  _tree[make]="${_tree[make]/guile}"
  _tree[pinentry]="${_tree[pinentry]/libsecret}"
  _tree[sudo]="${_tree[sudo]/libldap}"
  _tree[curl]="${_tree[curl]/krb5}"
  _tree[libtirpc]="${_tree[libtirpc]/krb5}"
  unset _tree[guile]
  unset _tree[gc]
  unset _tree[libsecret]
  unset _tree[libldap]
  unset _tree[krb5]

  # write package dependency tree
  truncate -s0 "$_deptree".FULL
  for i in "${!_tree[@]}"; do
    echo "${i} : [${_tree[$i]} ]" >> "$_deptree".FULL
  done
  # we need filesystem to be early, for directories and symlinks
  sed -i "/^filesystem/d; 1ifilesystem : [${_tree[filesystem]} ]" "$_deptree".FULL
  cp "$_deptree"{.FULL,}
fi

[ -n "${CONTINUE:-}" ] || cp "$_deptree"{.FULL,}

echo "total pkges: $(cat "$_deptree".FULL | wc -l)"
