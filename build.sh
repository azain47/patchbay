#!/bin/bash
set -euo pipefail

NAME="patchbay"
DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/$NAME.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
OBJ="$DIR/.DSPConfig.o"
ICON_HELPER="$DIR/.LogoIcon.swift"
ICON_BUILDER="$DIR/.logo-icon-builder"
ICONSET="$APP/Contents/Resources/AppIcon.iconset"
trap 'rm -f "$OBJ" "$ICON_HELPER" "$ICON_BUILDER"; rm -rf "$ICONSET"' EXIT

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
    "$DIR/Logo.swift" \
    "$DIR/Routing.swift" \
    "$DIR/MicEngine.swift" \
    "$DIR/Squig.swift" \
    "$DIR/EQFit.swift" \
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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAudioCaptureUsageDescription</key>
    <string>patchbay needs access to process system audio through your effects rack.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>patchbay reads your microphone to run it through the microphone chain into patchbay Mic.</string>
</dict>
</plist>
EOF

mkdir -p "$APP/Contents/Resources"
cat > "$ICON_HELPER" <<'EOF'
import Cocoa

@main
struct LogoIconBuilder {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "LogoIconBuilder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "missing iconset output path"])
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sizes: [(String, CGFloat)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024)
        ]
        for (name, size) in sizes {
            let image = Logo.appIcon(size: size)
            guard let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
                  let png = rep.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "LogoIconBuilder", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "could not encode \(name)"])
            }
            try png.write(to: directory.appendingPathComponent(name), options: .atomic)
        }
    }
}
EOF

swiftc \
    -O \
    -target arm64-apple-macosx15.0 \
    -framework Cocoa \
    -framework SwiftUI \
    -o "$ICON_BUILDER" \
    "$DIR/Logo.swift" \
    "$ICON_HELPER"

"$ICON_BUILDER" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"
bash "$DIR/VirtualMic/build.sh" "$APP/Contents/Resources" 2>&1 | grep -E "error|built" || true

codesign -s - --force --deep "$APP" 2>/dev/null

echo "built $APP"
