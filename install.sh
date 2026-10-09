#!/bin/bash
# Installs or updates ChatBar from the latest GitHub release.
#
#   curl -fsSL https://raw.githubusercontent.com/peter-iglaev/combine-chat-widget/main/install.sh | bash
#
# The DMG is fetched with curl, so macOS does not quarantine it and the unsigned app
# launches normally and shows up in Spotlight. Its SHA-256 is checked against the
# checksum published with the release.
set -euo pipefail

REPO="peter-iglaev/combine-chat-widget"
DEST="/Applications/ChatBar.app"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "ChatBar currently supports Apple Silicon Macs only." >&2
  exit 1
fi

echo "==> Looking up the latest release"
API="https://api.github.com/repos/$REPO/releases/latest"
URLS="$(curl -fsSL "$API" | grep -o '"browser_download_url": *"[^"]*"' | sed 's/.*"\(https[^"]*\)"/\1/')"
DMG_URL="$(echo "$URLS" | grep '\.dmg$' | head -1)"
SUM_URL="$(echo "$URLS" | grep '\.dmg\.sha256$' | head -1)"
if [[ -z "$DMG_URL" || -z "$SUM_URL" ]]; then
  echo "Could not find the DMG and its checksum in the latest release." >&2
  exit 1
fi

TMP="$(mktemp -d)"
MNT="$TMP/mnt"
cleanup() {
  hdiutil detach "$MNT" -quiet >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

echo "==> Downloading $(basename "$DMG_URL")"
curl -fsSL "$DMG_URL" -o "$TMP/ChatBar.dmg"
EXPECTED="$(curl -fsSL "$SUM_URL" | awk '{print $1}')"
ACTUAL="$(shasum -a 256 "$TMP/ChatBar.dmg" | awk '{print $1}')"
if [[ "$EXPECTED" != "$ACTUAL" ]]; then
  echo "Checksum mismatch: expected $EXPECTED, got $ACTUAL" >&2
  exit 1
fi

echo "==> Installing to $DEST"
mkdir -p "$MNT"
hdiutil attach "$TMP/ChatBar.dmg" -mountpoint "$MNT" -nobrowse -quiet
osascript -e 'tell application id "io.github.peter-iglaev.chatbar" to quit' >/dev/null 2>&1 || true
pkill -f "$DEST/Contents/MacOS/ChatBar" >/dev/null 2>&1 || true
rm -rf "$DEST"
ditto "$MNT/ChatBar.app" "$DEST"
# Clears a quarantine flag left by an earlier manual install from a browser download.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "==> Launching ChatBar"
open "$DEST"
echo "Done. Press ⌘Y to open the chat list."
