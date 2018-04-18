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

# shellcheck source=src/stage4/makepkg.sh
. "$TOPSRCDIR"/stage4/makepkg.sh
# shellcheck source=src/stage4/chroot.sh
. "$TOPSRCDIR"/stage4/chroot.sh

stage4_makepkg() {
  local pkgname="${1%-breakdeps}"
  local prefix=()
  [ "x$1" != "x$pkgname" ] && prefix=(-r -p breakdeps)

  package_fetch_upstream_pkgfiles "$pkgname" || return
  package_patch "${prefix[@]}" "$pkgname" || return
  package_import_keys "$pkgname" || return

  # substitute common variables
  sed "s#@MULTILIB@#${MULTILIB:-disable}#g" \
    PKGBUILD.in > PKGBUILD

  # prepare the pkgbuild
  package_enable_arch "$CARCH"
  echo "checkdepends=()" >> PKGBUILD

  # check built dependencies
  local dep
  for dep in $(srcinfo_builddeps -n); do
    deptree_check_depend "$1" "$dep" || return
  done
  for dep in $(srcinfo_rundeps "$pkgname"); do
    deptree_check_depend "$1" "$dep" || return
  done

  if ! deptree_is_satisfyable "$1"; then
    # add a temporary -breakdeps build, if a patch exists
    if [ "x$1" == "x$pkgname" ] && package_has_patch -p breakdeps "$1"; then
      deptree_add_entry "$1-breakdeps" "$1"
      sed -i "s/ /  /g; s/ $pkgname / $pkgname-breakdeps /g; s/  */ /g" "$DEPTREE"
    fi
    # postpone actual build
    return 0
  fi

  # don't rebuild if already exists
  check_pkgfile "$PKGPOOL" "$1" && return

  # prepare the chroot
  yes | librechroot \
      -n "$CHOST-stage4" \
      -C "$BUILDDIR"/config/pacman.conf \
      -M "$BUILDDIR"/config/makepkg.conf \
    run pacman -Scc || return

  # build the package
  "$BUILDDIR/libremakepkg-$CARCH.sh" -n "$CHOST"-stage4 || return
}

stage4_package_build() {
  local pkgname="${1%-breakdeps}"
  local pkgarch
  pkgarch=$(pkgarch "$pkgname") || return

  # clean staging
  rm -f "$PKGDEST"/*

  if [ "x$pkgarch" == "xany" ]; then
    package_reuse_upstream "$pkgname" || return
  else
    stage4_makepkg "$1" || return
  fi

  # postpone on unmet dependencies
  deptree_is_satisfyable "$1" || return 0

  # release built packages
  shopt -s nullglob
  local pkgfiles=("$PKGDEST"/*)
  shopt -u nullglob

  local file name repo
  for file in "${pkgfiles[@]}"; do
    file="$(basename "$file")"
    name="${file%-*-*-*}"
    echo -n "checking for $name upstream repo ..."
    repo=$(package_get_upstream_repo "$name")
    echo "$repo"

    if [ "x$1" != "x$pkgname" ]; then
      mv "$PKGDEST/$file" "$PKGDEST/${file/$name/$name-breakdeps}" || return
      file="${file/$name/$name-breakdeps}"
      name="$name-breakdeps"
    else
      rm -f "$PKGPOOL/${file/$name/$name-breakdeps}" \
            "$PKGPOOL/../$repo/os/$CARCH/${file/$name/$name-breakdeps}"
    fi

    pushd "$PKGDEST/../$repo/os/$CARCH" >/dev/null || return

    ln -fs ../../../pool/"$file" "$file" || return
    mv "$PKGDEST/$file" "$PKGPOOL" || return
    repo-add -q -R "$repo.db.tar.gz" "$PKGPOOL/$file" || return

    popd >/dev/null || return
  done
}

stage4_package_install() {
  local esc pkgfile
  esc=$(printf '%s\n' "$1" | sed 's:[][\/.+^$*]:\\&:g')
  pkgfile=$(find "$PKGPOOL" -regex "^.*/$esc-[^-]*-[^-]*-[^-]*\\.pkg\\.tar\\.xz\$" | head -n1)
  [ -n "$pkgfile" ] || { error -n "$1: pkgfile not found"; return "$ERROR_MISSING"; }

  librechroot \
      -n "$CHOST-stage4" \
      -C "$BUILDDIR"/config/pacman.conf \
      -M "$BUILDDIR"/config/makepkg.conf \
    run pacman -U --noconfirm /repos/pool/"$(basename "$pkgfile")" || return
  yes | librechroot \
      -n "$CHOST-stage4" \
      -C "$BUILDDIR"/config/pacman.conf \
      -M "$BUILDDIR"/config/makepkg.conf \
    run pacman -Syyuu || return
}

stage4() {
  msg -n "Entering Stage 4"

  local groups=(base base-devel)

  export BUILDDIR="$TOPBUILDDIR"/stage4
  export SRCDIR="$TOPSRCDIR"/stage4
  export MAKEPKGDIR="$BUILDDIR"/$CARCH-makepkg
  export DEPTREE="$BUILDDIR"/DEPTREE
  export PKGDEST="$BUILDDIR"/packages/staging
  export PKGPOOL="$BUILDDIR"/packages/pool
  export LOGDEST="$BUILDDIR"/makepkglogs
  export DEPPATH=("$PKGPOOL" "${BUILDDIR/stage4/stage3}/packages/$CARCH")

  mkdir -p "$PKGDEST" "$PKGPOOL" "$LOGDEST"
  chown "$SUDO_USER" "$PKGDEST" "$PKGPOOL" "$LOGDEST"

  binfmt_enable

  prepare_deptree "${groups[@]}" || die -e "$ERROR_BUILDFAIL" "failed to prepare DEPTREE"
  echo "remaining pkges: $(wc -l < "$DEPTREE") / $(wc -l < "$DEPTREE".FULL)"
  [ -s "$DEPTREE" ] || return 0

  prepare_stage4_makepkg || die -e "$ERROR_BUILDFAIL" "failed to prepare $CARCH makepkg"
  prepare_stage4_chroot || die -e "$ERROR_BUILDFAIL" "failed to prepare $CARCH chroot"

  check_exe -r librechroot libremakepkg

  # build packages from deptree
  packages_build_all stage4_package_build stage4_package_install || return

  # cleanup
  umount_stage4_chrootdir
}
