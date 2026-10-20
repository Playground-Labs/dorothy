#!/bin/bash
# Builds build/Dorothy.app (app + dorothy-mcp + fonts), ad-hoc signed.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN=$(swift build -c release --show-bin-path)
APP=build/Dorothy.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts"
cp "$BIN/Dorothy" "$BIN/dorothy-mcp" "$APP/Contents/MacOS/"
cp Resources/Fonts/*.ttf Resources/Fonts/OFL-*.txt "$APP/Contents/Resources/Fonts/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>ai.nextwork.dorothy</string>
    <key>CFBundleName</key><string>Dorothy</string>
    <key>CFBundleExecutable</key><string>Dorothy</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>Dorothy listens while you hold ⌃⌥D so Gemma can turn speech into to-dos.</string>
</dict>
</plist>
PLIST

codesign --force --deep -s - "$APP"
echo "Built $APP"
