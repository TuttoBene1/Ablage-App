#!/bin/bash
# Builds Ablage.app as a universal binary (Apple silicon + Intel).
#
#   ./build.sh            → build/Ablage.app
#   ./build.sh --install  → also copies it to /Applications and launches it
#   ./build.sh --release  → also creates dist/Ablage.dmg and dist/Ablage-macOS.zip
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-}"
APP="build/Ablage.app"
BUNDLE_ID="de.webforging.ablage"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
ARCHS=(--arch arm64 --arch x86_64)

echo "› Building Ablage $VERSION (Apple silicon + Intel) …"
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/Ablage"

echo "› Assembling app bundle …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Ablage"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ ! -f Resources/AppIcon.icns ]; then
  echo "› Rendering app icon …"
  rm -rf build/AppIcon.iconset
  swift Scripts/make-icon.swift build/AppIcon.iconset >/dev/null
  iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns Resources/WebforgingLogo.png "$APP/Contents/Resources/"

echo "› Signing …"
# A stable certificate keeps the screen-recording permission across updates.
if [ -n "${SIGNING_IDENTITY:-}" ]; then
  codesign --force --sign "$SIGNING_IDENTITY" ${SIGNING_KEYCHAIN:+--keychain "$SIGNING_KEYCHAIN"} \
    --identifier "$BUNDLE_ID" "$APP"
elif [ -z "${CI:-}" ] && KEYCHAIN="$(Scripts/signing.sh 2>/dev/null)"; then
  codesign --force --sign "Ablage Local Signing" --keychain "$KEYCHAIN" --identifier "$BUNDLE_ID" "$APP"
else
  echo "  (ad-hoc signature)"
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
fi
codesign --verify --strict "$APP"

if [ "$MODE" = "--release" ]; then
  echo "› Packaging release …"
  rm -rf dist build/dmg
  mkdir -p dist build/dmg
  ditto -c -k --keepParent "$APP" dist/Ablage-macOS.zip
  ditto "$APP" build/dmg/Ablage.app
  ln -s /Applications build/dmg/Applications
  hdiutil create -quiet -volname "Ablage $VERSION" -srcfolder build/dmg -ov -format UDZO dist/Ablage.dmg
  (cd dist && shasum -a 256 Ablage.dmg Ablage-macOS.zip > SHA256SUMS.txt)
  echo "  dist/Ablage.dmg, dist/Ablage-macOS.zip"
fi

if [ "$MODE" = "--install" ]; then
  echo "› Installing to /Applications …"
  pkill -x Ablage 2>/dev/null || true
  sleep 0.5
  rm -rf /Applications/Ablage.app
  ditto "$APP" /Applications/Ablage.app
  open /Applications/Ablage.app
fi

echo "✓ Done: $APP"
