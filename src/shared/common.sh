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

retry() {
  for i in $(seq $(expr $1 - 1)); do
    "${@:2}" && return 0 || sleep 20;
  done
  "${@:2}" || return;
}

import_keys() {
  local keys="$(source ${1:-PKGBUILD} && echo "${validpgpkeys[@]}")"
  [ -z "$keys" ] || retry 3 sudo -u $SUDO_USER gpg --recv-keys $keys || return
}

fetch_pkgfiles() {
  # acquire the pkgbuild and auxiliary files
  local libre=https://www.parabola.nu/packages/libre/x86_64/$1/
  local core=https://www.archlinux.org/packages/core/x86_64/$1/
  local extra=https://www.archlinux.org/packages/extra/x86_64/$1/
  local community=https://www.archlinux.org/packages/community/x86_64/$1/
  local url
  for url in $libre $core $extra $community; do
    if ! curl -s $url | grep -iq 'not found'; then
      local src=$(curl -s $url | grep -i 'source files' | cut -d'"' -f2 | sed 's#/tree/#/plain/#')
      for link in $(curl -sL $src | grep '^  <li><a href' | cut -d"'" -f2 \
          | sed "s#^#$(echo $src | awk -F/ '{print $3}')#"); do
        wget -q $link -O $(basename ${link%\?*});
      done
      break
    fi
  done
  [ -f PKGBUILD ] || return
}
