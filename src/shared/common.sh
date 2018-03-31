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

# shellcheck source=src/shared/feedback.sh
. "$TOPSRCDIR"/shared/feedback.sh
# shellcheck source=src/shared/checks.sh
. "$TOPSRCDIR"/shared/checks.sh
# shellcheck source=src/shared/srcinfo.sh
. "$TOPSRCDIR"/shared/srcinfo.sh
# shellcheck source=src/shared/pacman.sh
. "$TOPSRCDIR"/shared/pacman.sh
# shellcheck source=src/shared/upstream.sh
. "$TOPSRCDIR"/shared/upstream.sh
# shellcheck source=src/shared/deptree.sh
. "$TOPSRCDIR"/shared/deptree.sh
# shellcheck source=src/shared/package.sh
. "$TOPSRCDIR"/shared/package.sh

retry() {
  local OPTIND o n=5 s=60
  while getopts "n:s:" o; do
    case "$o" in
      n) n="$OPTARG" ;;
      s) s="$OPTARG" ;;
      *) die -e $ERROR_INVOCATION "Usage: ${FUNCNAME[0]} [-n tries] [-s delay] cmd ..." ;;
    esac
  done
  shift $((OPTIND-1))

  for _ in $(seq "$((n - 1))"); do
    "$@" && return 0
    sleep "$s"
  done
  "$@" || return
}

runas() {
  sudo -u "$1" --preserve-env=PKGDEST,LOGDEST,SRCDEST "${@:2}"
}

prepare_makepkgdir() {
  rm -rf "$1"
  mkdir -p "$1"
  chown -R "$SUDO_USER" "$1"

  pushd "$1" >/dev/null || return 1
}

binfmt_enable() {
  echo 1 > /proc/sys/fs/binfmt_misc/status
}

binfmt_disable() {
  echo 0 > /proc/sys/fs/binfmt_misc/status
}
