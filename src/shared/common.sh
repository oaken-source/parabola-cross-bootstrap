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
    "${@:3}" && return 0 || sleep $2;
  done
  "${@:3}" || return;
}

import_keys() {
  local keys="$(source ${1:-PKGBUILD} && echo "${validpgpkeys[@]}")"
  if [ -n "$keys" ]; then
    local key
    for key in $keys; do
      echo -n "checking for key $key ... "
      sudo -u $SUDO_USER gpg --list-keys $key &>/dev/null && _have_key=yes || _have_key=no
      echo $_have_key
      if [ "x$_have_key" == "xno" ]; then
        retry 5 60 sudo -u $SUDO_USER gpg --recv-keys $key \
          || die "failed to import key $key"
      fi
    done
  fi
}

_fetch_pkgfiles_from() {
  curl -sL $url | grep -iq 'not found' && return 1
  local src=$(curl -sL $url | grep -i 'source files' | cut -d'"' -f2 | sed 's#/tree/#/plain/#')
  for link in $(curl -sL $src | grep '^  <li><a href' | cut -d"'" -f2 \
      | sed "s#^#$(echo $src | awk -F/ '{print $3}')#"); do
    wget -q $link -O $(basename ${link%\?*});
  done
  [ -f PKGBUILD ] || return 1
}

fetch_pkgfiles() {
  # acquire the pkgbuild and auxiliary files
  local url=https://www.parabola.nu/packages/libre/x86_64/$1/
  _fetch_pkgfiles_from $url && echo "libre" > .REPO && return

  local repo
  for repo in core extra community; do
    url=https://www.archlinux.org/packages/$repo/x86_64/$1/
    _fetch_pkgfiles_from $url && echo "$repo" > .REPO && return
  done
  die "$1: failed to fetch pkgfiles"
}

prepare_makepkgdir() {
  rm -rf "$_makepkgdir"/$_pkgname
  mkdir -p "$_makepkgdir"/$_pkgname
  pushd "$_makepkgdir"/$_pkgname >/dev/null
  chown -R $SUDO_USER "$_makepkgdir"/$_pkgname
}

failed_build() {
  _log=$(find "$_logdest" -type f -iname "$1-*" -printf "%T@ %p\n" \
      | sort -n | tail -n1 | cut -d' ' -f2-)
  set +o pipefail
  _phase=""
  [ -z "$_log" ] || _phase=$(cat $_log | grep '==>.*occurred in' \
      | awk '{print $7}' | sed 's/().*//')
  set -o pipefail
  if [ -n "${_phase:-}" ]; then
    notify -c error "$_pkgname: error in $_phase()" -h string:document:"$_log"
  else
    notify -c error "$_pkgname: error in makepkg"
  fi
  [ "x$KEEP_GOING" == "xyes" ] || die "error building $_pkgname"
  _build_failed=yes
}

make_realdep() {
  local dep

  dep="$1"
  _realdep=$(pacman --noconfirm -Sddw "$dep" \
    | grep '^Packages' | awk '{print $3}')
  [ -n "$_realdep" ] && _realdep="${_realdep%-*-*}" && return 0

  dep="$(echo "$dep" | sed 's/[<>=].*//')"
  _realdep=$(pacman --noconfirm -Sddw "$dep" \
    | grep '^Packages' | awk '{print $3}')
  [ -n "$_realdep" ] && _realdep="${_realdep%-*-*}" && return 0

  return 0
}
