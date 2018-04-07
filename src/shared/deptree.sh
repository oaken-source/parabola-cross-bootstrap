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
  truncate -s0 "$DEPTREE".FULL || return

  # add the packages listed in the given groups
  local g p r
  for g in "$@"; do
    for p in $(pacman -Sg "$g" | awk '{print $2}'); do
      r=$(make_realpkg "$p") || return "$ERROR_MISSING"
      deptree_add_entry "$r" "$g"
    done
  done

  return 0
}

prepare_deptree() {
  check_deptree || build_deptree "$@" || return

  [ -f "$DEPTREE" ] || cp "$DEPTREE"{.FULL,}
  chown "$SUDO_USER" "$DEPTREE"{,.FULL}
}

deptree_next() {
  local pkg
  pkg=$(grep '\[ *\]' "$DEPTREE" | head -n1 | awk '{print $1}')
  [ -n "$pkg" ] || return "$ERROR_MISSING"
  echo "$pkg"
}

deptree_remove() {
  sed -i "/^$1 :/d; s/ /  /g; s/ $1 / /g; s/  */ /g" "$DEPTREE"
}

deptree_is_satisfyable() {
  grep -q "^$1 : \\[ *\\]" "$DEPTREE"
}

deptree_check_depend() {
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

  local r
  r=$(make_realpkg "$1") || return

  local blacklist
  blacklist=$(grep "^$r:" "$TOPSRCDIR"/blacklist.txt)

  if [ -n "$blacklist" ]; then
    error -n "$pkg: bad dependency $r: $(cut -d':' -f2 <<< "$blacklist")"
    return "$ERROR_MISSING"
  fi

  deptree_add_entry "$r" "$pkg"

  local have_pkg=no
  local path
  for path in "${DEPPATH[@]}"; do
    check_pkgfile "$path" "$r" && { have_pkg=yes; break; }
    check_pkgfile -p "breakdeps" "$path" "$r" && { have_pkg=yes; break; }
  done

  if [ "x$needed" == "xyes" ] && [ "x$have_pkg" == "xno" ]; then
    sed -i "s/^$pkg : \\[/& $r/" "$DEPTREE"{,.FULL}
  fi
}

deptree_add_entry() {
  local r="${2:-<cmdline>}"

  if grep -q "^$1 :" "$DEPTREE".FULL; then
    # if pkg is in deptree, append requestee to list
    sed -i "/#.* $r\\(\$\\|[ ,]\\)/! s/^$1 : \\[.*/&, $r/" "$DEPTREE"*
  elif grep -q "^$r :" "$DEPTREE".FULL; then
    # elif requestee is in deptree, insert after requestee
    sed -i "/^$r :/a $1 : [ ] # $r" "$DEPTREE"*
  elif [ "x$r" == "x<cmdline>" ]; then
    # elif requested directly, add to top of file
    sed -i "1i $1 : [ ] # $r" "$DEPTREE"*
  else
    # else append to deptree
    echo "$1 : [ ] # $r" >> "$DEPTREE".FULL
    [ -f "$DEPTREE" ] && echo "$1 : [ ] # $r" >> "$DEPTREE"
  fi
}
