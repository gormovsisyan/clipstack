#!/bin/bash
# Builds Clipstack.app into ./build.
#   ./build.sh            build the app bundle
#   ./build.sh --run      build, then launch it
#   ./build.sh --install  build, then copy to /Applications and launch
#   ./build.sh --package  build, then zip the bundle to build/Clipstack.zip
#
# VERSION=1.2.0 stamps CFBundleShortVersionString; BUILD_NUMBER stamps CFBundleVersion.
#
# Set SIGN_IDENTITY to a certificate name (e.g. a self-signed "Code Signing" cert
# made in Keychain Access) so macOS keeps the Accessibility grant across rebuilds.
# The default ad-hoc signature ("-") changes every build, which resets that grant.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Clipstack"
APP_DIR="build/$APP_NAME.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

if ! swift build -c release; then
  echo "swift build failed" >&2
  exit 1
fi
BIN=".build/release/$APP_NAME"

mkdir -p build
if [ ! -f build/AppIcon.icns ]; then
  echo "Generating app icon…"
  swift Scripts/make-icon.swift build/AppIcon.icns
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_DIR/Contents/Info.plist"
if [ -n "${VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"
fi
if [ -n "${BUILD_NUMBER:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"
fi
cp build/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

codesign --force --sign "$SIGN_IDENTITY" --identifier com.gormovsisyan.clipstack "$APP_DIR" 2>&1 | grep -v 'replacing existing signature' || true
echo "Built $APP_DIR"

case "${1:-}" in
  --run)
    pkill -x "$APP_NAME" 2>/dev/null || true
    open "$APP_DIR"
    ;;
  --package)
    rm -f "build/$APP_NAME.zip"
    ditto -c -k --norsrc --keepParent "$APP_DIR" "build/$APP_NAME.zip"
    echo "Packaged build/$APP_NAME.zip"
    ;;
  --install)
    pkill -x "$APP_NAME" 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_DIR" "/Applications/$APP_NAME.app"
    echo "Installed /Applications/$APP_NAME.app"
    open "/Applications/$APP_NAME.app"
    ;;
esac
