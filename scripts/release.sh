#!/bin/bash
# Packages a release into dist/: patchbay.dmg and appcast.xml (the Sparkle update feed).
#
#   VERSION=1.4.0 SPARKLE_KEY_FILE=path/to/ed25519.key NOTES_FILE=notes.md scripts/release.sh
#
# The app and DMG are signed with the "patchbay Code Signing" certificate, which must be in
# the keychain. The appcast describes only this release; it is attached to the GitHub release
# and the app reads it from /releases/latest/download/appcast.xml.
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
: "${VERSION:?set VERSION, e.g. 1.4.0}"
: "${SPARKLE_KEY_FILE:?set SPARKLE_KEY_FILE to the Sparkle EdDSA private key}"
IDENTITY="patchbay Code Signing"
DIST="$DIR/dist"
REPO="https://github.com/azain47/patchbay"

VERSION="$VERSION" SIGN_IDENTITY="$IDENTITY" bash "$DIR/build.sh"

rm -rf "$DIST" && mkdir -p "$DIST"
npx --yes create-dmg@8 --overwrite --no-version-in-filename --no-code-sign "$DIR/patchbay.app" "$DIST" >/dev/null
codesign --force --sign "$IDENTITY" "$DIST/patchbay.dmg"
codesign --verify "$DIST/patchbay.dmg"

# generate_appcast embeds release notes found next to the archive with the same base name.
if [ -n "${NOTES_FILE:-}" ] && [ -s "$NOTES_FILE" ]; then cp "$NOTES_FILE" "$DIST/patchbay.md"; fi
"$DIR/.build/Sparkle-2.10.0/bin/generate_appcast" \
    --ed-key-file "$SPARKLE_KEY_FILE" \
    --download-url-prefix "$REPO/releases/download/v$VERSION/" \
    --embed-release-notes \
    --link "$REPO" \
    -o "$DIST/appcast.xml" \
    "$DIST"
rm -f "$DIST/patchbay.md"

echo "dist: $(ls "$DIST" | tr '\n' ' ')"
