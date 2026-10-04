#!/bin/bash
# Builds Snapboard.app into ./build. Run from the snapboard folder:  ./scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Building Snapboard (this takes a minute the first time)…"
swift build -c release

APP="build/Snapboard.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Snapboard" "$APP/Contents/MacOS/Snapboard"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Snapboard</string>
    <key>CFBundleDisplayName</key><string>Snapboard</string>
    <key>CFBundleIdentifier</key><string>com.alexi.snapboard</string>
    <key>CFBundleExecutable</key><string>Snapboard</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Snapboard reads the song playing in Spotify or Music for the Now playing widget. It never controls them.</string>
</dict>
</plist>
PLIST

# Sign it for this Mac only (free, no Apple Developer account needed).
codesign --force --deep --sign - "$APP"

echo ""
echo "Done: $(pwd)/$APP"
echo "Drag it into your Applications folder, then open it from there."
