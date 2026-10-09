#!/bin/zsh
# Packs build/ChatBar.app into build/ChatBar-<version>.dmg (+ .sha256) with an Applications shortcut.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${CHATBAR_VERSION:-0.1.0}"
APP="$ROOT/build/ChatBar.app"
DMG="$ROOT/build/ChatBar-$VERSION.dmg"
STAGE="$(mktemp -d)"

[[ -d "$APP" ]] || { echo "Run scripts/build.sh first" >&2; exit 1; }

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "ChatBar" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
(cd "$(dirname "$DMG")" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "Done: $DMG"
