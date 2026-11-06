#!/usr/bin/env bash
# Kodmoz Screen — .app paketi üretir.
# Kullanım: ./scripts/build.sh [--universal]
#   --universal : hem arm64 hem x86_64 derle.
set -euo pipefail

KOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$KOK/mac"

APP_ADI="Kodmoz Screen"
BUNDLE="$KOK/build/${APP_ADI}.app"
EXE="KodmozScreen"
UNIVERSAL=0
[ "${1:-}" = "--universal" ] && UNIVERSAL=1

echo "== 1) derleme =="
BUILD_ARGS=(-c release --product "$EXE")
if [ "$UNIVERSAL" -eq 1 ]; then
  BUILD_ARGS+=(--arch arm64 --arch x86_64)
  echo "   hedef: arm64 + x86_64 (evrensel)"
fi
swift build "${BUILD_ARGS[@]}"

BIN="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/$EXE"
[ -x "$BIN" ] || { echo "HATA: binary bulunamadı: $BIN" >&2; exit 1; }

echo "== 2) ikon =="
rm -rf "$KOK/build/icon"
mkdir -p "$KOK/build/icon"
"$BIN" --make-icon "$KOK/build/icon" >/dev/null
if command -v iconutil >/dev/null 2>&1; then
  rm -f "$KOK/build/AppIcon.icns"
  iconutil -c icns "$KOK/build/icon/AppIcon.iconset" -o "$KOK/build/AppIcon.icns"
  echo "   AppIcon.icns üretildi"
else
  echo "   UYARI: iconutil yok — ikonsuz devam"
fi

echo "== 3) .app iskeleti =="
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/$EXE"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
if [ -f "$KOK/build/AppIcon.icns" ]; then
  cp "$KOK/build/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
fi
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

if VERSION_TAG="$(git -C "$KOK" describe --tags --abbrev=0 2>/dev/null)" \
   && [[ "$VERSION_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION_TAG#v}" \
    "$BUNDLE/Contents/Info.plist" 2>/dev/null || true
  echo "   sürüm: ${VERSION_TAG#v} (git etiketi)"
fi

echo "== 4) imza =="
# Sabit kimlik, Ekran Kaydı ve Erişilebilirlik izinlerinin sonraki
# derlemelerde korunmasını sağlar.
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -1)"
ENTITLEMENTS="$KOK/mac/Resources/KodmozScreen.entitlements"
if [ -n "$IDENTITY" ] \
   && codesign --force --deep --sign "$IDENTITY" --identifier com.kodmoz.screen \
        --entitlements "$ENTITLEMENTS" --options runtime "$BUNDLE" >/dev/null 2>&1; then
  echo "   imzalandı: $IDENTITY"
elif codesign --force --deep --sign - --identifier com.kodmoz.screen \
        --entitlements "$ENTITLEMENTS" "$BUNDLE" 2>/dev/null; then
  echo "   ad-hoc imzalandı"
else
  echo "   UYARI: codesign başarısız (uygulama yine çalışır)"
fi

echo "== 5) doğrulama =="
plutil -lint "$BUNDLE/Contents/Info.plist" >/dev/null && echo "   Info.plist geçerli"
test -x "$BUNDLE/Contents/MacOS/$EXE" && echo "   binary çalıştırılabilir"
codesign --verify --strict "$BUNDLE" 2>/dev/null && echo "   imza doğrulandı" \
  || echo "   UYARI: imza doğrulanamadı"

echo ""
echo "Paket hazır: $BUNDLE"
