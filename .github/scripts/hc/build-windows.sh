#!/bin/bash
# =====================================================================
#  .github/scripts/hc/build-windows.sh — static Windows executables
# =====================================================================
#    build-windows.sh <x86|x64|arm64> <version> <out dir>
#
#  solvespace.exe and solvespace-cli.exe for one architecture, renamed
#  SolveSpace-<version>-windows-<arch>.exe and
#  solvespace-cli-<version>-windows-<arch>.exe. Visual Studio 2022 with the
#  static C runtime (/MT, set by the top-level CMakeLists) and the bundled
#  libraries, so each executable needs only Windows' own DLLs; this script
#  refuses to hand over one that needs anything else.
#
#  Single-core (no OpenMP): MSVC's OpenMP runtime is VCOMP140.DLL, which has
#  no static form, and the fork stays on MSVC, upstream's Windows compiler.
#  (MinGW-w64 GCC with a static libgomp was proven for x64 but not for x86 or
#  arm64; not taken.)
#
#  Runs under the runner's bash (Git for Windows), as upstream's scripts do.
#  No tests: those run offline.
#  SPDX-License-Identifier: GPL-3.0-or-later
# =====================================================================
set -euo pipefail
ARCH=${1:?usage: build-windows.sh <x86|x64|arm64> <version> <out dir>}
VERSION=${2:?version}
OUT=${3:?out dir}
case $ARCH in
    x86)   PLATFORM=Win32 ;;
    x64)   PLATFORM=x64 ;;
    arm64) PLATFORM=ARM64 ;;
    *) echo "unknown arch $ARCH" >&2; exit 2 ;;
esac
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
B=$ROOT/build-hc-$ARCH
rm -rf "$B"
ARCH_ARGS=()
if [ "$ARCH" = arm64 ]; then
    # Upstream has never built for Windows on Arm, and two bundled libraries
    # assume x86 under MSVC. pixman hard-wires MMX, SSE2 and SSSE3 on for MSVC
    # without testing the target, though a value given on the command line
    # wins. ANGLE tests only for 32-bit Arm (!defined(_M_ARM)) in two places,
    # so on arm64 it defines ANGLE_USE_SSE (platform.h, which compiles the
    # SSE2 image loaders) and calls the x86-only __cpuid (mathutil.h). The
    # edit adds _M_ARM64 beside each, is idempotent, and is checked per file.
    ARCH_ARGS=(-DUSE_X86_MMX=OFF -DUSE_SSE2=OFF -DUSE_SSSE3=OFF)
    for M in "$ROOT/extlib/angle/src/common/platform.h" "$ROOT/extlib/angle/src/common/mathutil.h"; do
        sed -i -E 's/!defined\(_M_ARM\)( && !defined\(_M_ARM64\))?/!defined(_M_ARM) \&\& !defined(_M_ARM64)/g' "$M"
        grep -q '!defined(_M_ARM) && !defined(_M_ARM64)' "$M" ||
            { echo "could not exclude arm64 in $M" >&2; exit 1; }
    done
fi
# The bundled ANGLE declares cmake_minimum_required below 3.5, which CMake 4
# refuses; CMAKE_POLICY_VERSION_MINIMUM lets it configure (CMake 3 ignores it).
cmake -S "$ROOT" -B "$B" -G "Visual Studio 17 2022" -A "$PLATFORM" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_OPENMP=OFF -DENABLE_LTO=ON \
    -DENABLE_TESTS=OFF -DENABLE_SANITIZERS=OFF \
    -DSOLVESPACE_HC_VERSION="$VERSION" \
    "${ARCH_ARGS[@]}"
cmake --build "$B" --config Release -- -maxcpucount

BIN=$B/bin/Release
VSWHERE="/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"
# dumpbin from whichever host tools this machine has: arm64-hosted on Windows
# on Arm, x64-hosted elsewhere.
DUMPBIN=$( { "$VSWHERE" -latest -products '*' -find 'VC/Tools/MSVC/*/bin/Hostarm64/arm64/dumpbin.exe'
             "$VSWHERE" -latest -products '*' -find 'VC/Tools/MSVC/*/bin/Hostx64/x64/dumpbin.exe'; } \
           | tr -d '\r' | grep -v '^$' | if [ "$(uname -m)" = aarch64 ] || [ "${PROCESSOR_ARCHITECTURE:-}" = ARM64 ]; then head -1; else tail -1; fi)
[ -n "$DUMPBIN" ] || { echo "dumpbin not found" >&2; exit 1; }
mkdir -p "$OUT"
for exe in solvespace solvespace-cli; do
    [ -f "$BIN/$exe.exe" ] || { echo "$BIN/$exe.exe was not built" >&2; exit 1; }
    # Every DLL it imports must be one Windows itself provides.
    deps=$("$DUMPBIN" -nologo -dependents "$BIN/$exe.exe" | tr -d '\r' | grep -iE '^\s+\S+\.dll$' | tr -d ' ')
    echo "$exe.exe imports: $(echo $deps)"
    extra=$(echo "$deps" | grep -viE '^(KERNEL32|USER32|GDI32|SHELL32|ADVAPI32|COMDLG32|OLE32|OLEAUT32|SHLWAPI|WS2_32|d3d9|dxgi|d3d11|d3dcompiler_47|IMM32|WINMM|VERSION|bcrypt|CRYPT32|COMCTL32|UxTheme|dwmapi|OPENGL32|GLU32|SETUPAPI|HID)\.dll$' || true)
    if [ -n "$extra" ]; then
        echo "$exe.exe needs DLLs Windows does not provide: $extra" >&2; exit 1
    fi
    name=$exe; [ $exe = solvespace ] && name=SolveSpace
    cp "$BIN/$exe.exe" "$OUT/$name-$VERSION-windows-$ARCH.exe"
done
ls -l "$OUT"
