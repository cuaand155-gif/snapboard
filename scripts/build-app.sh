#!/bin/bash
# Builds Snapboard.app into ./build. Run from the snapboard folder:  ./scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# UNIVERSAL=1 builds one app that runs on both Apple-silicon and Intel Macs (used by GitHub).
ARCH_FLAGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi

echo "Building Snapboard (this takes a minute the first time)…"
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}

APP="build/Snapboard.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/Snapboard" "$APP/Contents/MacOS/Snapboard"

# The app icon: Resources/AppIcon.png (drawn by scripts/make-icon.py) turned into an .icns.
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Snapboard</string>
    <key>CFBundleDisplayName</key><string>Snapboard</string>
    <key>CFBundleIdentifier</key><string>com.alexi.snapboard</string>
    <key>CFBundleExecutable</key><string>Snapboard</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
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
