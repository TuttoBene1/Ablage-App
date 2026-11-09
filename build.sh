#!/bin/bash
# Builds Ablage.app as a universal binary (Apple silicon + Intel).
#
#   ./build.sh            → build/Ablage.app
#   ./build.sh --install  → also copies it to /Applications and starts it
#   ./build.sh --release  → also creates dist/Ablage.dmg and dist/Ablage-macOS.zip
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-}"
APP="build/Ablage.app"
BUNDLE_ID="de.webforging.ablage"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
ARCHS=(--arch arm64 --arch x86_64)

echo "› Kompiliere Ablage $VERSION (Apple Silicon + Intel) …"
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/Ablage"

echo "› Erzeuge App-Bundle …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Ablage"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ ! -f Resources/AppIcon.icns ]; then
  echo "› Erzeuge App-Symbol …"
  rm -rf build/AppIcon.iconset
  swift Scripts/make-icon.swift build/AppIcon.iconset >/dev/null
  iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "› Signiere …"
# A stable certificate keeps macOS' screen-recording permission across updates.
if [ -n "${SIGNING_IDENTITY:-}" ]; then
  # CI: certificate imported from repository secrets.
  codesign --force --sign "$SIGNING_IDENTITY" ${SIGNING_KEYCHAIN:+--keychain "$SIGNING_KEYCHAIN"} \
    --identifier "$BUNDLE_ID" "$APP"
elif [ -z "${CI:-}" ] && KEYCHAIN="$(Scripts/signing.sh 2>/dev/null)"; then
  # Local: self-signed certificate created by Scripts/signing.sh.
  codesign --force --sign "Ablage Local Signing" --keychain "$KEYCHAIN" --identifier "$BUNDLE_ID" "$APP"
else
  echo "  (ad-hoc signiert)"
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
fi
codesign --verify --strict "$APP"

if [ "$MODE" = "--release" ]; then
  echo "› Packe Release …"
  rm -rf dist build/dmg
  mkdir -p dist build/dmg
  ditto -c -k --keepParent "$APP" dist/Ablage-macOS.zip
  ditto "$APP" build/dmg/Ablage.app
  ln -s /Applications build/dmg/Programme
  hdiutil create -quiet -volname "Ablage $VERSION" -srcfolder build/dmg -ov -format UDZO dist/Ablage.dmg
  (cd dist && shasum -a 256 Ablage.dmg Ablage-macOS.zip > SHA256SUMS.txt)
  echo "  dist/Ablage.dmg, dist/Ablage-macOS.zip"
fi

if [ "$MODE" = "--install" ]; then
  echo "› Installiere nach /Applications …"
  pkill -x Ablage 2>/dev/null || true
  sleep 0.5
  rm -rf /Applications/Ablage.app
  ditto "$APP" /Applications/Ablage.app
  open /Applications/Ablage.app
fi

echo "✓ Fertig: $APP"
