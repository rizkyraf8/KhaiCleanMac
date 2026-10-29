#!/bin/bash
# Packs KhaiCleanMac.app into build/KhaiCleanMac-<version>.dmg: a Finder window with the app, an
# Applications shortcut to drag it onto, and a background with install notes.
# Usage: scripts/make-dmg.sh [--skip-build]   (--skip-build reuses the app already in ./build)
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
NAME="KhaiCleanMac"
APP="$ROOT/build/$NAME.app"

if [[ "${1:-}" != "--skip-build" ]]; then
    "$ROOT/scripts/build-app.sh"
fi
[[ -d "$APP" ]] || { echo "✗ $APP tidak ada, jalankan scripts/build-app.sh dulu" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/build/$NAME-$VERSION.dmg"
# Finder addresses the disk by its volume name, so a mounted copy would get the layout instead.
if [[ -d "/Volumes/$NAME" ]]; then
    echo "✗ /Volumes/$NAME sedang terpasang, eject dulu" >&2
    exit 1
fi

WORK="$(mktemp -d)"
MOUNT=""
cleanup() {
    [[ -n "$MOUNT" ]] && hdiutil detach "$MOUNT" -quiet -force 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

echo "→ Membuat latar DMG"
swiftc -O -o "$WORK/background" "$ROOT/scripts/make-dmg/background.swift"
"$WORK/background" "$WORK/background.png"

echo "→ Menyusun isi DMG"
STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/$NAME.app"
ln -s /Applications "$STAGE/Applications"
cp "$WORK/background.png" "$STAGE/.background/background.png"
cp "$ROOT/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"

hdiutil create -quiet -volname "$NAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$WORK/rw.dmg"
MOUNT="$(hdiutil attach "$WORK/rw.dmg" -readwrite -noverify -noautoopen | grep -o '/Volumes/.*$')"
# Custom-icon flag (0x0400 in the FinderInfo flags) on the volume root, so Finder shows .VolumeIcon.icns.
xattr -wx com.apple.FinderInfo "0000000000000000040000000000000000000000000000000000000000000000" "$MOUNT"

echo "→ Mengatur jendela Finder (macOS bisa minta izin mengontrol Finder)"
# Window is 660×400 like the background; icon positions match scripts/make-dmg/background.swift.
# Without permission the DMG still works (app + Applications shortcut), just without the arranged window.
osascript <<EOF || echo "⚠︎ Finder menolak, jadi jendela DMG memakai tata letak bawaan. Untuk tata letak rapi, izinkan di System Settings › Privacy & Security › Automation, lalu ulangi" >&2
tell application "Finder"
    tell disk "$NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 860, 548}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.png"
        set position of item "$NAME.app" of container window to {170, 190}
        set position of item "Applications" of container window to {490, 190}
        -- With hidden files shown, Finder would auto-place these at the top, pushing the window's origin
        -- (and every icon) down past the arrow. Parked below the window they leave the layout alone.
        set hiddenX to 100
        repeat with hiddenName in {".background", ".VolumeIcon.icns", ".fseventsd", ".DS_Store"}
            try
                set position of item (hiddenName as text) of container window to {hiddenX, 700}
            end try
            set hiddenX to hiddenX + 150
        end repeat
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF
# Give Finder time to write .DS_Store before the disk is detached.
sync
sleep 2
hdiutil detach "$MOUNT" -quiet
MOUNT=""

echo "→ Kompres ke $DMG"
hdiutil convert -quiet "$WORK/rw.dmg" -format ULFO -ov -o "$DMG"
shasum -a 256 "$DMG" | sed "s|$ROOT/build/||" > "$DMG.sha256"

echo "✓ Selesai: $DMG ($(du -h "$DMG" | cut -f1))"
echo "  SHA-256: $(cut -d' ' -f1 "$DMG.sha256")"
