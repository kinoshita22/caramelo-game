#!/usr/bin/env bash
# Builds the Windows game and its installer.
#
#   tools/build_windows_installer.sh
#
# Needs: godot 4.4.1 with Windows export templates, and NSIS 3 (makensis).
# Set MAKENSIS (and NSISDIR for a locally built makensis) if makensis is not
# on PATH. Output: build/windows/MyCaramelo.exe and
# build/windows/MyCaramelo-Setup-<version>.exe.
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
MAKENSIS="${MAKENSIS:-makensis}"
VERSION="$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)"
OUT="build/windows"

echo "== My Caramelo ${VERSION}"
mkdir -p "$OUT"
echo "== icon"
"$GODOT" --headless --path . --script res://tools/make_app_icon.gd
echo "== game (Windows export)"
"$GODOT" --headless --path . --export-release "Windows Desktop" "$OUT/MyCaramelo.exe"
test -s "$OUT/MyCaramelo.exe"
echo "== installer"
"$MAKENSIS" -V2 -DVERSION="$VERSION" -DBUILD_DIR="$(pwd)/$OUT" installer/caramelo.nsi
ls -la "$OUT"
