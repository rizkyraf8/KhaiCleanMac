#!/bin/bash
# Builds KhaiCleanMac.app into ./build (ad-hoc signed, for local use).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/build/KhaiCleanMac.app"
ICON="$ROOT/Resources/AppIcon.icns"
ARTWORK="$ROOT/Sources/KhaiCleanMac/Design/LogoArtwork.swift"

if [[ ! -f "$ICON" || "$ARTWORK" -nt "$ICON" ]]; then
    echo "→ Membuat ikon aplikasi"
    WORK="$(mktemp -d)"
    swiftc -O -o "$WORK/make-icon" "$ROOT/scripts/make-icon/main.swift" "$ARTWORK"
    "$WORK/make-icon" "$WORK/icon.png"
    ICONSET="$WORK/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z $size $size "$WORK/icon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        sips -z $((size * 2)) $((size * 2)) "$WORK/icon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$ICON"
    rm -rf "$WORK"
fi

# Universal by default, so the same app runs on Apple silicon and Intel Macs.
# KHAI_ARCH=arm64 (or x86_64) builds a single slice, which is quicker while developing.
case "${KHAI_ARCH:-universal}" in
    universal) ARCHS=(--arch arm64 --arch x86_64) ;;
    arm64|x86_64) ARCHS=(--arch "$KHAI_ARCH") ;;
    *) echo "✗ KHAI_ARCH harus universal, arm64, atau x86_64" >&2; exit 1 ;;
esac
echo "→ Compile (release, ${KHAI_ARCH:-universal})"
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/KhaiCleanMac"

echo "→ Menyusun $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/KhaiCleanMac"
echo "→ Arsitektur: $(lipo -archs "$APP/Contents/MacOS/KhaiCleanMac")"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

# An ad-hoc signature changes on every build, and macOS then silently drops the Full Disk Access
# grant. A stable certificate keeps it: create a "KhaiCleanMac Local" code-signing certificate in
# Keychain Access (Certificate Assistant → Create a Certificate, type Code Signing) or set
# KHAI_SIGN_IDENTITY to any identity you already have.
IDENTITY="${KHAI_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]] && security find-identity -p codesigning 2>/dev/null | grep -q '"KhaiCleanMac Local"'; then
    IDENTITY="KhaiCleanMac Local"
fi
if [[ -n "$IDENTITY" ]]; then
    echo "→ Sign dengan \"$IDENTITY\""
    codesign --force --sign "$IDENTITY" "$APP" >/dev/null
else
    echo "→ Sign ad-hoc (izin Akses Disk Penuh perlu diberikan ulang setiap build)"
    codesign --force --sign - "$APP" >/dev/null
fi
echo "✓ Selesai: $APP"
