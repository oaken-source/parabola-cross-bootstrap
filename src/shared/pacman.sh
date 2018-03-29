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

import_keys() {
  local keys k
  keys="$(srcinfo_validpgpkeys)"
  for k in $keys; do
    check_gpgkey "$k" && continue
    if ! retry -n 5 -s 60 sudo -u "$SUDO_USER" gpg --recv-keys "$k"; then
      error -n "failed to import key '$k'"
      return "$ERROR_KEYFAIL"
    fi
  done
}

pkgdeps() {
  pacman -Si "$1" | grep '^Depends' | cut -d':' -f2 | sed 's/None//'
}

pkgarch() {
  local pkgarch
  pkgarch=$(pacman -Si "$1" | grep '^Architecture' | awk '{print $3}') || return
  [ -n "$pkgarch" ] || return

  # set arch to $CARCH, unless it is any
  [ "x$pkgarch" == "xany" ] || pkgarch="$CARCH"
  echo "$pkgarch"
}

pkgver() {
  local pkgver
  pkgver=$(pacman -Si "$1" | grep '^Version' | awk '{print $3}') || return
  [ -n "$pkgver" ] || return
  echo "$pkgver"
}

make_realpkg() {
  local dep realpkg

  dep="$1"
  realpkg=$(pacman --noconfirm -Sddw "$dep" | grep '^Packages' | awk '{print $3}')
  [ -n "$realpkg" ] && echo "${realpkg%-*-*}" && return 0

  dep="$(sed 's/[<>=].*//' <<< "$dep")"
  realpkg=$(pacman --noconfirm -Sddw "$dep" | grep '^Packages' | awk '{print $3}')
  [ -n "$realpkg" ] && echo "${realpkg%-*-*}" && return 0

  return "$ERROR_MISSING"
}

make_repo() {
  local path=$1
  shift

  mkdir -p "$path" || return

  local v
  for v in "$@"; do
    tar -czf "$path"/"$v".db.tar.gz -T /dev/null
    tar -czf "$path"/"$v".files.tar.gz -T /dev/null
    ln -s "$v".db.tar.gz "$path"/"$v".db
    ln -s "$v".files.tar.gz "$path"/"$v".files
  done
}
