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

check_deptree() {
  echo -n "checking for complete deptree ... "

  local have_deptree=yes
  [ -f "$DEPTREE".FULL ] || have_deptree=no
  echo $have_deptree

  [ "x$have_deptree" == "xyes" ] || return "$ERROR_MISSING"
}

build_deptree() {
  check_exe ed pacman sed || return

  # create empty deptree
  truncate -s0 "$DEPTREE".FULL

  # add the packages listed in the given groups
  local g p r
  for g in "$@"; do
    for p in $(pacman -Sg "$g" | awk '{print $2}'); do
      r=$(make_realpkg "$p") || return "$ERROR_MISSING"

      if ! grep -q "^$r :" "$DEPTREE".FULL; then
        echo "$r : [ ] # $g" >> "$DEPTREE".FULL
      else
        sed -i "s/^$r : \\[.*/&, $g/" "$DEPTREE".FULL
      fi
    done
  done
}

prepare_deptree() {
  check_deptree || build_deptree "$@" || return

  [ -f "$DEPTREE" ] || cp "$DEPTREE"{.FULL,}
  chown "$SUDO_USER" "$DEPTREE"{,.FULL}
}

deptree_next() {
  local pkg
  pkg=$(grep '\[ *\]' "$DEPTREE" | tail -n1 | awk '{print $1}')
  [ -n "$pkg" ] || return "$ERROR_MISSING"
  echo "$pkg"
}

deptree_remove() {
  sed -i "/^$1 :/d; s/ /  /g; s/ $1 / /g; s/  */ /g" "$DEPTREE"
}

deptree_check_depends() {
  local OPTIND o needed=yes
  while getopts "n" o; do
    case "$o" in
      n) needed=no ;;
      *) die -e "$ERROR_INVOCATION" "Usage: ${FUNCNAME[0]} [-p] deptree pkgname depend" ;;
    esac
  done
  shift $((OPTIND-1))

  local pkg="$1"
  shift

  local dep r res=0
  # shellcheck disable=SC2068
  for dep in $@; do
    r=$(make_realpkg "$dep") || { res="$ERROR_MISSING"; continue; }

    local have_pkg=yes
    check_pkgfile "$PKGDEST" "$r" || have_pkg=no

    if ! grep -q "^$r :" "$DEPTREE".FULL; then
      echo "$r : [ ] # $pkg" >> "$DEPTREE".FULL
      echo "$r : [ ] # $pkg" >> "$DEPTREE"
    else
      sed -i "/#.* $pkg\\(\\$\\|[ ,]\\)/! s/^$r : \\[.*/&, $pkg/" "$DEPTREE"{,.FULL}
    fi
    if [ "x$needed" == "xyes" ] && [ "x$have_pkg" == "xno" ]; then
      sed -i "s/^$pkg : \\[/& $r/" "$DEPTREE"{,.FULL}
    fi
  done

  return "$res"
}
