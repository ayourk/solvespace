#!/bin/bash
# =====================================================================
#  .github/scripts/hc/libomp-macos.sh — a static libomp for one arch
# =====================================================================
#  LLVM's OpenMP runtime as a static libomp.a, so the release DMGs link
#  OpenMP in and bundle no libomp.dylib. Homebrew stopped publishing an
#  x86_64 libomp (upstream #1777), and a static archive is what the
#  HobbyCAD build wants anyway.
#
#    libomp-macos.sh <arm64|x86_64> [cache dir]
#
#  Prints the install prefix (with include/ and lib/libomp.a) on its last
#  line. Built once per version and arch into the cache dir (default
#  ~/Developer/ci-cache, which survives between runs on the self-hosted
#  runner) from a sparse checkout of the llvm-project tag. Deployment
#  target: 10.12 for x86_64 (SolveSpace's own minimum), 11.0 for arm64
#  (the first macOS on Apple Silicon).
#  SPDX-License-Identifier: GPL-3.0-or-later
# =====================================================================
set -euo pipefail
ARCH=${1:?usage: libomp-macos.sh <arm64|x86_64> [cache dir]}
CACHE=${2:-$HOME/Developer/ci-cache}
VER=23.1.1
TAG=llvmorg-$VER
case $ARCH in
    x86_64) TARGET=10.12 ;;
    arm64)  TARGET=11.0 ;;
    *) echo "unknown arch $ARCH" >&2; exit 2 ;;
esac
PREFIX=$CACHE/libomp-$VER-static-$ARCH
if [ -f "$PREFIX/lib/libomp.a" ] && [ -f "$PREFIX/include/omp.h" ]; then
    echo "libomp $VER ($ARCH) cached" >&2
    echo "$PREFIX"; exit 0
fi

SRC=$CACHE/llvm-project-$VER
if [ ! -d "$SRC/.git" ]; then
    rm -rf "$SRC"
    git clone --filter=blob:none --sparse --depth 1 --branch "$TAG" \
        https://github.com/llvm/llvm-project.git "$SRC" >&2
    git -C "$SRC" sparse-checkout set cmake runtimes openmp llvm/cmake \
        llvm/utils/llvm-lit third-party >&2
fi

B=$CACHE/libomp-build-$VER-$ARCH
rm -rf "$B" "$PREFIX.part"
cmake -S "$SRC/runtimes" -B "$B" -G Ninja \
    -DLLVM_ENABLE_RUNTIMES=openmp -DLIBOMP_ENABLE_SHARED=OFF \
    -DLIBOMP_INSTALL_ALIASES=OFF -DOPENMP_ENABLE_OMPT_TOOLS=OFF \
    -DLLVM_INCLUDE_TESTS=OFF -DOPENMP_ENABLE_TESTING=OFF \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$TARGET" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX.part" >&2
cmake --build "$B" >&2
cmake --install "$B" >&2
# Installed whole or not at all: a half-written prefix must not look cached.
mv "$PREFIX.part" "$PREFIX"
lipo -archs "$PREFIX/lib/libomp.a" >&2
echo "$PREFIX"
