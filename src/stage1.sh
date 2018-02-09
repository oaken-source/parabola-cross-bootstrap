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

set -eu

_group="base base-devel"

msg "creating transitive dependency tree for $_group"
declare -A _tree
_frontier=($(pacman -Sg $_group | cut -d' ' -f2))
while [ ${#_frontier[@]} -gt 0 ]; do
  # pop pkg from frontier
  _pkg=$(echo ${_frontier[0]})
  _frontier=("${_frontier[@]:1}")
  # if seen before, skip, otherwise create entry in dependency tree
  [[ -v _tree[$_pkg] ]] && continue
  _tree[$_pkg]=""
  # iterate dependencies for pkg
  _deps="$(echo $(pacman -Si $_pkg | grep '^Depends' | cut -d':' -f2 | sed 's/None//'))"
  for dep in $_deps; do
    # translate dependency string to actual package
    realdep=$(yes n | pacman --confirm -Sd "$dep" 2>&1 | grep '^Packages' \
              | cut -d' ' -f3 | rev | cut -d'-' -f3- | rev)
    # add dependency to tree and frontier
    _tree[$_pkg]="${_tree[$_pkg]} $realdep"
    _frontier+=($realdep)
  done
done

# log package dependency tree
echo "" > "$_builddir"/.deptree
for i in "${!_tree[@]}"; do
  echo "  ${i} : [${_tree[$i]} ]" >> "$_builddir"/.deptree
done
echo "total pkges: ${#_tree[@]}"

msg "preparing the ${_target%%-*} chroot"
_chrootdir="$_builddir"/${_target%%-*}-root
rm -rvf "$_chrootdir"
mkdir -pv "$_chrootdir"

# create required directories
mkdir -pv "$_chrootdir"/{etc/pacman.d/{gnupg,hooks},var/{lib/pacman,cache/pacman/pkg,log}}

# create pacman.conf
cat > "$_chrootdir"/etc/pacman.conf << EOF
[options]
RootDir = $_chrootdir
DBPath = $_chrootdir/var/cache/pacman/
CacheDir = $_chrootdir/var/cache/pacman/pkg/
LogFile = $_chrootdir/var/log/pacman.log
GPGDir = $_chrootdir/etc/pacman.d/gnupg
HookDir = $_chrootdir/etc/pacman.d/hooks
Architecture = ${_target%%-*}

[repo]
SigLevel = Never
Server = file://$_chrootdir/packages/\$arch
EOF

# create a local package directory
mkdir -vp "$_chrootdir"/packages/${_target%%-*}
repo-add -n "$_chrootdir"/packages/${_target%%-*}/{repo.db.tar.gz,*}

# test and initialize ALPM library
pacman --config "$_chrootdir"/etc/pacman.conf -r "$_chrootdir" -Syyu
#pacman --config "$_chrootdir"/etc/pacman.conf -r "$_chrootdir" -Q

msg "preparing the ${_target%%-*} build environment"
_makepkgdir="$_builddir"/${_target%%-*}-build
rm -rvf "$_makepkgdir"
mkdir -pv "$_makepkgdir"

# create a modified makepkg
cp -v /usr/bin/makepkg $_builddir/makepkg-${_target%%-*}
# patch run_pacman in makepkg, we cannot pass the pacman root to it as parameter ATM
sed -i "/\"\$PACMAN_PATH\"/a --config $_chrootdir/etc/pacman.conf -r $_chrootdir" \
  $_builddir/makepkg-${_target%%-*}

# create temporary makepkg.conf
cat > $_builddir/makepkg-${_target%%-*}.conf << EOF
DLAGENTS=('ftp::/usr/bin/curl -fC - --ftp-pasv --retry 3 --retry-delay 3 -o %o %u'
          'http::/usr/bin/curl -fLC - --retry 3 --retry-delay 3 -o %o %u'
          'https::/usr/bin/curl -fLC - --retry 3 --retry-delay 3 -o %o %u'
          'rsync::/usr/bin/rsync --no-motd -z %u %o'
          'scp::/usr/bin/scp -C %u %o')
VCSCLIENTS=('bzr::bzr'
            'git::git'
            'hg::mercurial'
            'svn::subversion')
CARCH="${_target%%-*}"
CHOST="$_target"
CPPFLAGS="-D_FORTIFY_SOURCE=2"
CFLAGS="-O2 -pipe -fstack-protector-strong -fno-plt"
CXXFLAGS="-O2 -pipe -fstack-protector-strong -fno-plt"
LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now"
DEBUG_CFLAGS="-g -fvar-tracking-assignments"
DEBUG_CXXFLAGS="-g -fvar-tracking-assignments"
BUILDENV=(!distcc color !ccache check !sign)
OPTIONS=(strip docs !libtool !staticlibs emptydirs zipman purge !optipng !upx !debug)
INTEGRITY_CHECK=(md5)
STRIP_BINARIES="--strip-all"
STRIP_SHARED="--strip-unneeded"
STRIP_STATIC="--strip-debug"
MAN_DIRS=({usr{,/local}{,/share},opt/*}/{man,info})
DOC_DIRS=(usr/{,local/}{,share/}{doc,gtk-doc} opt/*/{doc,gtk-doc})
PURGE_TARGETS=(usr/{,share}/info/dir .packlist *.pod)
COMPRESSGZ=(gzip -c -f -n)
COMPRESSBZ2=(bzip2 -c -f)
COMPRESSXZ=(xz -c -z -)
COMPRESSLRZ=(lrzip -q)
COMPRESSLZO=(lzop -q)
COMPRESSZ=(compress -c -f)
PKGEXT='.pkg.tar.xz'
SRCEXT='.src.tar.gz'
EOF

_pkgname=gcc-libs-shim
_pkgver=$(pacman -Qi $_target-gcc | grep '^Version' | cut -d':' -f2 | tr -d [:space:])
msg "creating pkg: $_pkgname-$_pkgver"

mkdir -pv "$_makepkgdir"/$_pkgname
pushd "$_makepkgdir"/$_pkgname

_pkgdir="$_makepkgdir"/$_pkgname/pkg/$_pkgname
mkdir -pv "$_pkgdir"/usr/lib
cp -aLv /usr/$_target/lib/lib{gcc_s.so{,.1},atomic.{a,so.1.2.0},stdc++.so.6.0.24} \
  "$_pkgdir"/usr/lib/
ln -vs libatomic.so.1.2.0 "$_pkgdir"/usr/lib/libatomic.so.1
ln -vs libatomic.so.1.2.0 "$_pkgdir"/usr/lib/libatomic.so
ln -vs libstdc++.so.6.0.24 "$_pkgdir"/usr/lib/libstdc++.so.6
ln -vs libstdc++.so.6.0.24 "$_pkgdir"/usr/lib/libstdc++.so
cat > "$_pkgdir"/.PKGINFO << EOF
pkgname = $_pkgname
pkgver = $_pkgver
pkgdesc = Runtime libraries shipped by GCC (extracted from $_target-gcc)
url = https://github.com/riscv/riscv-gnu-toolchain
builddate = $(date '+%s')
size = $(( $(du -sk --apparent-size "$_pkgdir" | cut -d'	' -f1) * 1024 ))
arch = ${_target%%-*}
provides = ${_pkgname%-*}
conflicts = ${_pkgname%-*}
EOF

cd "$_pkgdir"
env LANG=C bsdtar -czf .MTREE \
  --format=mtree \
  --options='!all,use-set,type,uid,gid,mode,time,size,md5,sha256,link' \
  .PKGINFO *
env LANG=C bsdtar -cf - .MTREE .PKGINFO * | xz -c -z - > \
  "$_chrootdir"/packages/${_target%%-*}/$_pkgname-$_pkgver-${_target%%-*}.pkg.tar.xz

popd

rm -rf "$_chrootdir"/var/cache/pacman/pkg/*
rm -rf "$_chrootdir"/packages/${_target%%-*}/repo.{db,files}*
repo-add -R "$_chrootdir"/packages/${_target%%-*}/{repo.db.tar.gz,*.pkg.tar.xz}
pacman --noconfirm --config "$_chrootdir"/etc/pacman.conf -r "$_chrootdir" -Syy $_pkgname
