#!/bin/bash
# Builds patchbayMic.driver: BlackHole (GPLv3, Existential Audio) compiled as a single
# 2-channel loopback device named "patchbay Mic". Whatever patchbay writes to its output
# stream appears on its input stream, so any app can pick "patchbay Mic" as a microphone.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$DIR/../patchbay.app/Contents/Resources}"
DRIVER="$OUT/patchbayMic.driver"
FACTORY_UUID="E395B3DA-0B9D-4C48-BDA9-5A7D1FA9A6C3"   # plug-in factory id, unique to this build

rm -rf "$DRIVER"
mkdir -p "$DRIVER/Contents/MacOS" "$DRIVER/Contents/Resources"

clang -bundle -O2 \
    -target arm64-apple-macosx14.0 \
    -framework CoreAudio -framework CoreFoundation -framework Accelerate \
    -DkDriver_Name='"patchbay Mic"' \
    -DkPlugIn_BundleID='"com.patchbay.mic"' \
    -DkHas_Driver_Name_Format=false \
    -DkDevice_Name='"patchbay Mic"' \
    -DkDevice2_Name='"patchbay Mic Mirror"' \
    -DkDevice2_IsHidden=true \
    -DkManufacturer_Name='"patchbay"' \
    -DkNumber_Of_Channels=2 \
    -DkSampleRates='44100, 48000, 96000' \
    -DkCanBeDefaultSystemDevice=false \
    -DkPlugIn_Icon='"patchbayMic.icns"' \
    -Wno-deprecated-declarations \
    -o "$DRIVER/Contents/MacOS/patchbayMic" \
    "$DIR/BlackHole.c"

cat > "$DRIVER/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>patchbayMic</string>
    <key>CFBundleIdentifier</key><string>com.patchbay.mic</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>patchbay Mic</string>
    <key>CFBundlePackageType</key><string>BNDL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFPlugInDynamicRegistration</key><string>NO</string>
    <key>CFPlugInFactories</key>
    <dict>
        <key>$FACTORY_UUID</key><string>BlackHole_Create</string>
    </dict>
    <key>CFPlugInTypes</key>
    <dict>
        <key>443ABAB8-E7B3-491A-B985-BEB9187030DB</key>
        <array><string>$FACTORY_UUID</string></array>
    </dict>
</dict>
</plist>
EOF
cp "$DIR/LICENSE" "$DRIVER/Contents/Resources/LICENSE"
codesign -s - --force "$DRIVER" 2>/dev/null
echo "built $DRIVER"
