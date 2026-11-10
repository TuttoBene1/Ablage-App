#!/bin/bash
# Installs (or updates) Ablage from the latest GitHub release.
#   curl -fsSL https://raw.githubusercontent.com/TuttoBene1/Ablage-App/main/install.sh | bash
set -euo pipefail

REPO="TuttoBene1/Ablage-App"
URL="https://github.com/$REPO/releases/latest/download/Ablage-macOS.zip"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Ablage runs on macOS only." >&2
  exit 1
fi
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$MAJOR" -lt 15 ]; then
  echo "Ablage requires macOS 15 Sequoia or later (found $(sw_vers -productVersion))." >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "› Downloading Ablage …"
curl -fL --progress-bar "$URL" -o "$TMP/Ablage.zip"
ditto -x -k "$TMP/Ablage.zip" "$TMP"

DEST="/Applications"
if [ ! -w "$DEST" ]; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
fi

echo "› Installing to $DEST …"
pkill -x Ablage 2>/dev/null || true
sleep 0.5
rm -rf "$DEST/Ablage.app"
ditto "$TMP/Ablage.app" "$DEST/Ablage.app"
xattr -dr com.apple.quarantine "$DEST/Ablage.app" 2>/dev/null || true

open "$DEST/Ablage.app"
echo "✓ Ablage is installed and running – look for its icon in the menu bar."
echo "  Made by Webforging · https://webforging.de/app-entwicklung"
