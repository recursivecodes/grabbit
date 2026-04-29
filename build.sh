#!/bin/bash
set -e

APP="Grabbit"
BUILD="build"
BUNDLE="$BUILD/$APP.app"
MACOS="$BUNDLE/Contents/MacOS"

rm -rf "$BUNDLE"
mkdir -p "$MACOS" "$BUNDLE/Contents/Resources"

echo "Compiling..."
swiftc Sources/*.swift \
    -o "$MACOS/$APP" \
    -framework AppKit \
    -framework Carbon \
    -framework CoreGraphics \
    -framework ScreenCaptureKit \
    -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
    -suppress-warnings \
    -O

cp Resources/Info.plist "$BUNDLE/Contents/"

echo "Generating icon..."
swift make_icon.swift "build/AppIcon.iconset"
iconutil -c icns "build/AppIcon.iconset" -o "$BUNDLE/Contents/Resources/AppIcon.icns"

echo "Done: $BUNDLE"
echo ""
echo "Run with:  open $BUNDLE"
echo "  or:      open build/Grabbit.app"
