#!/bin/bash
# =====================================================================
#  .github/scripts/hc/build-flatpak.sh — a Flatpak bundle
# =====================================================================
#    build-flatpak.sh <version> <out dir>
#
#  SolveSpace-<version>-linux-<arch>.flatpak for the machine's own
#  architecture, from upstream's manifest (pkg/flatpak), which builds the
#  gtkmm stack and SolveSpace from this tree. Only the version this build
#  reports is added, to a copy of the manifest. Installs with
#  `flatpak install --user <file>`; the Freedesktop runtime comes from
#  Flathub. No tests: those run offline.
#  SPDX-License-Identifier: GPL-3.0-or-later
# =====================================================================
set -euo pipefail
VERSION=${1:?usage: build-flatpak.sh <version> <out dir>}
OUT=${2:?out dir}
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
ARCH=$(uname -m)
SUDO=; [ "$(id -u)" = 0 ] || SUDO=sudo
APP=com.solvespace.SolveSpace
MANIFEST=$ROOT/pkg/flatpak/$APP.json

command -v flatpak-builder >/dev/null || {
    $SUDO apt-get update -qq
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -q -y flatpak flatpak-builder python3
}
RUNTIME_VERSION=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["runtime-version"])' "$MANIFEST")
flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install --user -y --noninteractive flathub \
    "org.freedesktop.Platform//$RUNTIME_VERSION" "org.freedesktop.Sdk//$RUNTIME_VERSION"

# The copy sits beside the original, so the manifest's "../.." source
# path still names this tree.
HC=$ROOT/pkg/flatpak/$APP.hc.json
python3 - "$MANIFEST" "$HC" "$VERSION" <<'PY'
import json, sys
src, dst, version = sys.argv[1:]
m = json.load(open(src))
for mod in m["modules"]:
    if isinstance(mod, dict) and mod.get("name") == "solvespace":
        mod.setdefault("config-opts", []).append("-DSOLVESPACE_HC_VERSION=" + version)
        break
else:
    sys.exit("no solvespace module in " + src)
json.dump(m, open(dst, "w"), indent=2)
PY

W=$ROOT/flatpak-hc
rm -rf "$W"
mkdir -p "$W"
flatpak-builder --user --force-clean --repo="$W/repo" --state-dir="$W/state" \
    "$W/build" "$HC"
mkdir -p "$OUT"
flatpak build-bundle "$W/repo" "$OUT/SolveSpace-$VERSION-linux-$ARCH.flatpak" "$APP"
rm -f "$HC"
ls -l "$OUT/SolveSpace-$VERSION-linux-$ARCH.flatpak"
