#!/bin/bash
# Installs (or updates) Ablage from the latest GitHub release.
#   curl -fsSL https://raw.githubusercontent.com/TuttoBene1/Ablage-App/main/install.sh | bash
set -euo pipefail

REPO="TuttoBene1/Ablage-App"
URL="https://github.com/$REPO/releases/latest/download/Ablage-macOS.zip"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Ablage läuft nur auf macOS." >&2
  exit 1
fi
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$MAJOR" -lt 15 ]; then
  echo "Ablage benötigt macOS 15 Sequoia oder neuer (gefunden: $(sw_vers -productVersion))." >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "› Lade Ablage herunter …"
curl -fL --progress-bar "$URL" -o "$TMP/Ablage.zip"
ditto -x -k "$TMP/Ablage.zip" "$TMP"

DEST="/Applications"
if [ ! -w "$DEST" ]; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
fi

echo "› Installiere nach $DEST …"
pkill -x Ablage 2>/dev/null || true
sleep 0.5
rm -rf "$DEST/Ablage.app"
ditto "$TMP/Ablage.app" "$DEST/Ablage.app"
# Downloaded via Terminal, so no Gatekeeper quarantine is needed.
xattr -dr com.apple.quarantine "$DEST/Ablage.app" 2>/dev/null || true

open "$DEST/Ablage.app"
echo "✓ Ablage ist installiert und läuft – das Symbol ist oben rechts in der Menüleiste."
echo "  Entwickelt von Webforging · https://webforging.de"
