#!/bin/bash
# Build Relaunch.app from source using swiftc (no Xcode project required).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Relaunch.app"

echo "==> Cleaning"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Writing Info.plist"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "==> Compiling"
swiftc \
    -swift-version 5 \
    -target arm64-apple-macos14.0 \
    -O \
    -framework AppKit \
    -framework SwiftUI \
    -framework ServiceManagement \
    -framework Carbon \
    -o "$APP/Contents/MacOS/Relaunch" \
    "$ROOT"/Sources/Relaunch/*.swift

echo "==> Ad-hoc signing"
codesign --force --sign - "$APP"

echo "==> Done: $APP"
echo "    Run with: open \"$APP\"   (or)   \"$APP/Contents/MacOS/Relaunch\""
