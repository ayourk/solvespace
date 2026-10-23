#!/bin/bash
# =====================================================================
#  .github/scripts/hc/build-macos.sh — one macOS DMG, one architecture
# =====================================================================
#    build-macos.sh <arm64|x86_64> <version> <out dir>
#
#  SolveSpace.app for one architecture, OpenMP linked in statically
#  (libomp-macos.sh), signed ad hoc, in a compressed DMG named
#  SolveSpace-<version>-macos-<arch>.dmg. Runs on the self-hosted Intel
#  Mac mini: x86_64 natively, arm64 cross-compiled. No tests: those run
#  offline. Ad hoc, not a Developer ID: the app runs, and Gatekeeper asks
#  once (right-click, Open). Without --options runtime, which an ad hoc
#  signature cannot satisfy.
#  SPDX-License-Identifier: GPL-3.0-or-later
# =====================================================================
set -euo pipefail
ARCH=${1:?usage: build-macos.sh <arm64|x86_64> <version> <out dir>}
VERSION=${2:?version}
OUT=${3:?out dir}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
export PATH=/usr/local/bin:$PATH
case $ARCH in
    x86_64) TARGET=10.12 ;;
    arm64)  TARGET=11.0 ;;
    *) echo "unknown arch $ARCH" >&2; exit 2 ;;
esac

OMP=$("$HERE/libomp-macos.sh" "$ARCH" | tail -1)
# The bundled libraries come from the checkout (actions/checkout with
# submodules); a tree without them cannot build the app.
for d in cairo freetype libdxfrw libpng pixman zlib eigen; do
    [ -n "$(ls -A "$ROOT/extlib/$d" 2>/dev/null)" ] \
        || { echo "extlib/$d is empty: check out with submodules" >&2; exit 1; }
done

B=$ROOT/build-hc-$ARCH
rm -rf "$B"
cmake -S "$ROOT" -B "$B" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$TARGET" \
    -DCMAKE_PREFIX_PATH="$OMP" \
    -DOpenMP_ROOT="$OMP" \
    -DENABLE_OPENMP=ON -DENABLE_LTO=ON \
    -DENABLE_TESTS=OFF -DENABLE_SANITIZERS=OFF \
    -DSOLVESPACE_HC_VERSION="$VERSION"
cmake --build "$B"

APP=$B/bin/SolveSpace.app
EXE=$APP/Contents/MacOS/SolveSpace
# The point of the static libomp: nothing outside the system is linked.
if otool -L "$EXE" "$APP/Contents/MacOS/solvespace-cli" | grep -E '\.dylib' \
        | grep -vE '^\s*/(usr/lib|System/Library)/' | grep -v ':$'; then
    echo "a non-system library is linked (above); the app would not be self-contained" >&2
    exit 1
fi
[ ! -e "$APP/Contents/Resources/libomp.dylib" ] \
    || { echo "libomp.dylib was bundled although OpenMP is static" >&2; exit 1; }
lipo -archs "$EXE"

codesign --force --deep -s - "$APP"
codesign --verify --deep --strict "$APP"

mkdir -p "$OUT"
DMG=$OUT/SolveSpace-$VERSION-macos-$ARCH.dmg
rm -f "$DMG"
hdiutil create -quiet -volname "SolveSpace $VERSION" -srcfolder "$APP" \
    -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG"
hdiutil verify -quiet "$DMG"
ls -l "$DMG"
