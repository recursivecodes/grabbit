#!/bin/bash
set -e

APP="Grabbit"
BUILD="build"
BUNDLE="$BUILD/$APP.app"
MACOS="$BUNDLE/Contents/MacOS"

rm -rf "$BUNDLE"
mkdir -p "$MACOS" "$BUNDLE/Contents/Resources"

echo "Compiling..."
ARCH=$(uname -m)  # arm64 or x86_64
TARGET="${ARCH}-apple-macos13.0"

swiftc Sources/*.swift \
    -o "$MACOS/$APP" \
    -framework AppKit \
    -framework Carbon \
    -framework CoreGraphics \
    -framework ScreenCaptureKit \
    -framework UserNotifications \
    -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
    -target "$TARGET" \
    -suppress-warnings \
    -O

cp Resources/Info.plist "$BUNDLE/Contents/"

echo "Generating icon..."
swift make_icon.swift "build/AppIcon.iconset"
iconutil -c icns "build/AppIcon.iconset" -o "$BUNDLE/Contents/Resources/AppIcon.icns"

echo "Signing..."
# Sign with a local "Grabbit Dev" certificate if available — this gives TCC
# a stable TeamID+BundleID pair so screen-recording permission persists across
# rebuilds. Create it once in Keychain Access → Certificate Assistant →
# Create a Certificate (Name: "Grabbit Dev", Type: Code Signing, Self Signed Root).
# Falls back to ad-hoc signing if the certificate isn't present.
if security find-certificate -c "Grabbit Dev" ~/Library/Keychains/login.keychain-db &>/dev/null; then
    codesign --force --deep --sign "Grabbit Dev" "$BUNDLE"
    echo "Signed with 'Grabbit Dev' certificate"
else
    codesign --force --deep --sign - "$BUNDLE"
    echo "Warning: 'Grabbit Dev' certificate not found, used ad-hoc signing."
    echo "         TCC will not persist screen-recording permission across rebuilds."
    echo "         See build.sh for instructions to create the certificate."
fi

echo "Done: $BUNDLE"
echo ""
echo "Run with:  open $BUNDLE"
echo "  or:      open build/Grabbit.app"
