#!/bin/zsh
# Собирает ChatBar.app в build/ и прописывает пути к сборщику.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/ChatBar"
swift build -c release
APP="$ROOT/build/ChatBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ChatBar "$APP/Contents/MacOS/ChatBar"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ChatBar</string>
  <key>CFBundleIdentifier</key><string>local.chatbar</string>
  <key>CFBundleExecutable</key><string>ChatBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>ChatBarPython</key><string>$ROOT/.venv/bin/python</string>
  <key>ChatBarCollector</key><string>$ROOT/collector/chatbar.py</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Готово: $APP"
