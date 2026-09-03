#!/bin/bash
set -euo pipefail

NAME="patchbay"
DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/$NAME.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc \
    -O \
    -whole-module-optimization \
    -target arm64-apple-macosx14.0 \
    -framework Cocoa \
    -framework SwiftUI \
    -framework CoreAudio \
    -suppress-warnings \
    -o "$APP/Contents/MacOS/$NAME" \
    "$DIR/main.swift"

cat > "$APP/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.patchbay.app</string>
    <key>CFBundleName</key>
    <string>patchbay</string>
    <key>CFBundleExecutable</key>
    <string>patchbay</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

codesign -s - --force "$APP" 2>/dev/null

echo "built $APP"
