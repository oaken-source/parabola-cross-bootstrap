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

# error codes
export ERROR_UNSPECIFIED=1
export ERROR_INVOCATION=2
export ERROR_MISSING=3
export ERROR_BUILDFAIL=4
export ERROR_KEYFAIL=5

# messaging functions
notify() {
  # useful if running notify_telegram
  local recipient=-211578786
  if type -p notify-send >/dev/null; then
    machinectl -q shell --uid="$SUDO_USER" .host \
      "$(which notify-send)" -h string:recipient:$recipient "$@" >/dev/null
  fi
}

msg() {
  local OPTIND o n='' d=()
  while getopts "d:n" o; do
    case "$o" in
      n) n=yes ;;
      d) d=(-h string:document:"$OPTARG") ;;
      *) die -e "$ERROR_INVOCATION" "Usage: ${FUNCNAME[0]} [-n] [-d file] msg ..." ;;
    esac
  done
  shift $((OPTIND-1))

  [ "x$n" == "xyes" ] && notify "${d[@]}" "${@//_/\\_}"
  echo "$(tput bold)$(tput setf 2)==>$(tput setf 7) $*$(tput sgr0)";
}

error() {
  local OPTIND o n='' d=()
  while getopts "d:n" o; do
    case "$o" in
      n) n=yes ;;
      d) d=(-h string:document:"$OPTARG") ;;
      *) die -e "$ERROR_INVOCATION" "Usage: ${FUNCNAME[0]} [-n] [-d file] msg ..." ;;
    esac
  done
  shift $((OPTIND-1))

  [ "x$n" == "xyes" ] && notify -c error "${d[@]}" "${@//_/\\_}"
  echo "$(tput bold)$(tput setf 4)==> ERROR:$(tput setf 7) $*$(tput sgr0)" 1>&2
}

die() {
  local OPTIND o e="$ERROR_UNSPECIFIED" d=()
  while getopts "e:d:" o; do
    case "$o" in
      e) e="$OPTARG" ;;
      d) d=(-d "$OPTARG") ;;
      *) die -e "$ERROR_INVOCATION" "Usage: ${FUNCNAME[0]} [-e status] [-d file] msg ..." ;;
    esac
  done
  shift $((OPTIND-1))

  error -n "${d[@]}" "$@"
  trap - ERR
  exit "$e"
}
trap 'die "unknown error"' ERR
