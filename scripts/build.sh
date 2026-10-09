#!/bin/zsh
# Builds a self-contained build/ChatBar.app: Swift binary + embedded Python + collector.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/ChatBar.app"
CACHE="$ROOT/build/cache"
VERSION="${CHATBAR_VERSION:-0.1.0}"

# Pinned standalone CPython (arm64), verified by checksum.
PY_URL="https://github.com/astral-sh/python-build-standalone/releases/download/20260901/cpython-3.12.14%2B20260901-aarch64-apple-darwin-install_only_stripped.tar.gz"
PY_SHA256="81a359f1cfadd4da11766534c5913791cea55f26e1bb902cacd2a531bb1e4b2b"
PY_TGZ="$CACHE/python-3.12.14-aarch64.tar.gz"

echo "==> Building Swift binary"
cd "$ROOT/ChatBar"
swift build -c release --arch arm64

echo "==> Assembling app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$CACHE"
cp .build/arm64-apple-macosx/release/ChatBar "$APP/Contents/MacOS/ChatBar"
cp -R "$ROOT/collector" "$APP/Contents/Resources/collector"
rm -rf "$APP/Contents/Resources/collector/__pycache__"

echo "==> Building icon"
ICONSET="$CACHE/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ROOT/assets/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$ROOT/assets/icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ChatBar</string>
  <key>CFBundleDisplayName</key><string>ChatBar</string>
  <key>CFBundleIdentifier</key><string>io.github.peter-iglaev.chatbar</string>
  <key>CFBundleExecutable</key><string>ChatBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

echo "==> Embedding Python"
if [[ ! -f "$PY_TGZ" ]] || ! echo "$PY_SHA256  $PY_TGZ" | shasum -a 256 -c - >/dev/null 2>&1; then
  curl -fsSL "$PY_URL" -o "$PY_TGZ"
fi
echo "$PY_SHA256  $PY_TGZ" | shasum -a 256 -c -
tar -xzf "$PY_TGZ" -C "$APP/Contents/Resources"   # creates Resources/python
PY="$APP/Contents/Resources/python/bin/python3"
"$PY" -m pip install --quiet --disable-pip-version-check --no-warn-script-location --no-deps \
  -r "$ROOT/collector/requirements.txt"
find "$APP/Contents/Resources/python" -name "__pycache__" -type d -prune -exec rm -rf {} +

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"

echo "Done: $APP"
