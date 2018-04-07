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

package_get_upstream_repo() {
  local repo repoinfo
  repoinfo=$(asp list-repos "$1" 2>/dev/null) || repoinfo=""
  repo=$(grep -P '^(core|extra|community)' <<< "$repoinfo" | head -n1)
  [ -z "$repo" ] && repo=libre
  echo "$repo"
}

package_fetch_upstream_pkgfiles() {
  # fetch upstream pkgbuilds from arch
  local repo repoinfo pkgbase
  repoinfo=$(asp list-repos "$1") || repoinfo=""
  repo=$(grep -P '^(core|extra|community)' <<< "$repoinfo" | head -n1)
  pkgbase=$(grep -o 'part of package .*' <<< "$repoinfo" | awk '{print $4}')

  [ -z "$repo" ] && repo=libre
  [ -z "$pkgbase" ] && pkgbase="$1"

  mkdir -p .arch
  asp export "$repo/$1" >/dev/null
  mv "$pkgbase"/* .arch/
  rm -rf "$pkgbase"

  # fetch upstream pkgbuilds from parabola
  mkdir -p .parabola
  local src url=https://www.parabola.nu/packages/libre/x86_64/$1/
  if ! curl -sL "$url" | grep -iq 'not found'; then
    src=$(curl -sL "$url" | grep -i 'source files' | cut -d'"' -f2 | sed 's#/tree/#/plain/#')
    for link in $(curl -sL "$src" | grep '^  <li><a href' | cut -d"'" -f2 \
        | sed "s#^#$(echo "$src" | awk -F/ '{print $3}')#"); do
      wget -q "$link" -O .parabola/"$(basename "${link%\?*}")";
    done
  fi

  if [ -f .parabola/PKGBUILD ]; then
    cp -v .parabola/* .
  elif [ -f .arch/PKGBUILD ]; then
    cp -v .arch/* .
  else
    return "$ERROR_MISSING"
  fi
}
