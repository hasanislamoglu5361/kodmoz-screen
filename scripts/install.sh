#!/usr/bin/env bash
# Kodmoz Screen'i /Applications'a kurar ve başlatır.
set -euo pipefail

KOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$KOK/build/Kodmoz Screen.app"
HEDEF="/Applications/Kodmoz Screen.app"

[ -d "$APP" ] || { echo "Önce ./scripts/build.sh çalıştırın." >&2; exit 1; }

osascript -e 'tell application "Kodmoz Screen" to quit' >/dev/null 2>&1 || true
pkill -x KodmozScreen >/dev/null 2>&1 || true
sleep 0.6

rm -rf "$HEDEF"
cp -R "$APP" "$HEDEF"
xattr -dr com.apple.quarantine "$HEDEF" 2>/dev/null || true

echo "Kuruldu: $HEDEF"
open "$HEDEF"
