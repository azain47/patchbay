#!/bin/bash
set -euo pipefail

NAME="patchbay"
DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/$NAME.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
OBJ="$DIR/.DSPConfig.o"
trap 'rm -f "$OBJ"' EXIT

clang \
    -O3 \
    -std=c11 \
    -target arm64-apple-macosx15.0 \
    -c "$DIR/DSPConfig.c" \
    -o "$OBJ"

swiftc \
    -O \
    -whole-module-optimization \
    -target arm64-apple-macosx15.0 \
    -import-objc-header "$DIR/DSPConfig.h" \
    -framework Cocoa \
    -framework SwiftUI \
    -framework CoreAudio \
    -framework AudioToolbox \
    -suppress-warnings \
    -o "$APP/Contents/MacOS/$NAME" \
    "$DIR/main.swift" \
    "$DIR/DSP.swift" \
    "$DIR/AudioEngine.swift" \
    "$DIR/UI.swift" \
    "$DIR/AutoEQ.swift" \
    "$OBJ"

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
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAudioCaptureUsageDescription</key>
    <string>patchbay needs access to process system audio through your effects rack.</string>
</dict>
</plist>
EOF

codesign -s - --force "$APP" 2>/dev/null

echo "built $APP"
