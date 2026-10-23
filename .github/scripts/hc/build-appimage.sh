#!/bin/bash
# =====================================================================
#  .github/scripts/hc/build-appimage.sh — a Linux AppImage
# =====================================================================
#    build-appimage.sh <version> <out dir>
#
#  SolveSpace-<version>-linux-<arch>.AppImage for the machine's own
#  architecture (x86_64 or aarch64), on Ubuntu 22.04 so the AppImage runs on
#  anything with that glibc or newer. GTK cannot be linked statically, so the
#  AppImage carries it instead: linuxdeploy and its GTK plugin bundle every
#  library the program loads, and the AppImage needs nothing installed.
#  OpenMP on (GCC's libgomp, bundled the same way). No tests: those run
#  offline.
#  SPDX-License-Identifier: GPL-3.0-or-later
# =====================================================================
set -euo pipefail
VERSION=${1:?usage: build-appimage.sh <version> <out dir>}
OUT=${2:?out dir}
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
ARCH=$(uname -m)
SUDO=; [ "$(id -u)" = 0 ] || SUDO=sudo

$SUDO apt-get update -qq
$SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -q -y --no-install-recommends \
    build-essential cmake ninja-build git file wget ca-certificates \
    zlib1g-dev libpng-dev libcairo2-dev libfreetype6-dev libjson-c-dev \
    libfontconfig1-dev libgtkmm-3.0-dev libpangomm-1.4-dev libgl-dev \
    libglu1-mesa-dev libspnav-dev libgtk-3-bin librsvg2-common

B=$ROOT/build-hc-appimage
APPDIR=$ROOT/AppDir-hc
rm -rf "$B" "$APPDIR"
cmake -S "$ROOT" -B "$B" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
    -DENABLE_OPENMP=ON -DENABLE_LTO=ON \
    -DENABLE_TESTS=OFF -DENABLE_SANITIZERS=OFF \
    -DSOLVESPACE_HC_VERSION="$VERSION"
cmake --build "$B"
DESTDIR=$APPDIR cmake --install "$B"

TOOLS=$ROOT/linuxdeploy-hc
mkdir -p "$TOOLS"
LD=$TOOLS/linuxdeploy-$ARCH.AppImage
[ -x "$LD" ] || { wget -q -O "$LD" "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-$ARCH.AppImage"; chmod +x "$LD"; }
GTK=$TOOLS/linuxdeploy-plugin-gtk.sh
[ -x "$GTK" ] || { wget -q -O "$GTK" "https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh"; chmod +x "$GTK"; }

DESKTOP=$(find "$APPDIR/usr/share/applications" -name '*.desktop' | head -1)
[ -n "$DESKTOP" ] || { echo "no .desktop file was installed" >&2; exit 1; }
# The installed entry runs /usr/bin/solvespace; inside an AppImage the
# program is found by name, and linuxdeploy accepts only a bare name.
sed -i -E 's|^(Exec=)/usr/bin/|\1|; s|^(TryExec=)/usr/bin/|\1|' "$DESKTOP"
grep -E '^Exec=' "$DESKTOP"
# Containers have no FUSE: let the tool AppImages unpack themselves instead.
export APPIMAGE_EXTRACT_AND_RUN=1
export DEPLOY_GTK_VERSION=3
export LDAI_OUTPUT="SolveSpace-$VERSION-linux-$ARCH.AppImage"
( cd "$TOOLS" && PATH=$TOOLS:$PATH "$LD" --appdir "$APPDIR" --plugin gtk \
      --desktop-file "$DESKTOP" --output appimage )
mkdir -p "$OUT"
mv "$TOOLS/$LDAI_OUTPUT" "$OUT/"
ls -l "$OUT/$LDAI_OUTPUT"
