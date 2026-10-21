#!/bin/bash
# Builds build/Dorothy.app (app + dorothy-mcp + fonts + Sparkle), ad-hoc signed.
# VERSION env sets the marketing version (default 1.0); the build number is the commit count (Sparkle compares it).
# --release: then Developer ID sign, notarize and staple it via notarize-app (apple-notarize-setup skill).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN=$(swift build -c release --show-bin-path)
APP=build/Dorothy.app
BUILD=$(git rev-list --count HEAD)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts" "$APP/Contents/Frameworks"
cp "$BIN/Dorothy" "$BIN/dorothy-mcp" "$APP/Contents/MacOS/"
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
otool -l "$APP/Contents/MacOS/Dorothy" | grep -q '@executable_path/../Frameworks' \
    || install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Dorothy"
cp Resources/Fonts/*.ttf Resources/Fonts/OFL-*.txt "$APP/Contents/Resources/Fonts/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>ai.nextwork.dorothy</string>
    <key>CFBundleName</key><string>Dorothy</string>
    <key>CFBundleExecutable</key><string>Dorothy</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION:-1.0}</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>SUFeedURL</key><string>https://github.com/Playground-Labs/dorothy/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key><string>o68qIoeBaUkzEQ3l3Y6qR0lvzdSufyaCMu5TPkbT2AY=</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>Dorothy listens while you hold ⌃⌥D so Gemma can turn speech into to-dos.</string>
</dict>
</plist>
PLIST

codesign --force --deep -s - "$APP"
echo "Built $APP"

if [[ "${1:-}" == --release ]]; then
    notarize-app "$APP" --entitlements Resources/Dorothy.entitlements
fi
