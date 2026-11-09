#!/bin/bash
# Makes sure a local, self-signed code-signing identity exists and prints the
# path of the keychain that holds it.
#
# Why: an ad-hoc signature changes with every build, so macOS treats each new
# build as a different app and forgets the screen-recording permission.
# Signing with the same certificate every time keeps the permission across updates.
# The identity lives in its own small keychain (not the login keychain).
set -euo pipefail

NAME="Ablage Local Signing"
DIR="$HOME/Library/Application Support/Ablage/Signing"
KEYCHAIN="$DIR/signing.keychain-db"
PASSFILE="$DIR/keychain-password"

mkdir -p "$DIR"
chmod 700 "$DIR"

if [ ! -f "$KEYCHAIN" ] || [ ! -f "$PASSFILE" ]; then
  rm -f "$KEYCHAIN" "$PASSFILE"
  umask 077
  openssl rand -hex 24 > "$PASSFILE"
  PASS="$(cat "$PASSFILE")"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT

  openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -subj "/CN=$NAME" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" >/dev/null 2>&1
  P12PASS="$(openssl rand -hex 12)"
  openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -out "$TMP/identity.p12" -passout "pass:$P12PASS"

  # create-keychain adds the new keychain to the search list; restore the list afterwards.
  ORIGINAL=()
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"; line="${line%\"}"; line="${line#\"}"
    [ -n "$line" ] && ORIGINAL+=("$line")
  done < <(security list-keychains -d user)

  security create-keychain -p "$PASS" "$KEYCHAIN"
  security list-keychains -d user -s "${ORIGINAL[@]}"
  security set-keychain-settings "$KEYCHAIN"
  security unlock-keychain -p "$PASS" "$KEYCHAIN"
  security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$P12PASS" -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KEYCHAIN" >/dev/null
fi

security unlock-keychain -p "$(cat "$PASSFILE")" "$KEYCHAIN"
echo "$KEYCHAIN"
