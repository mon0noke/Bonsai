#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PWD/outputs/${BONSAI_APP_NAME:-Bonsai}.app/Contents/Info.plist")
APP="$PWD/outputs/${BONSAI_APP_NAME:-Bonsai}.app"
APP_BUNDLE="$(basename "$APP")"
[[ -x "$APP/Contents/MacOS/Bonsai" ]] || { echo 'Build Bonsai first.' >&2; exit 1; }
codesign --verify --strict "$APP"
STAGE="$PWD/work/Bonsai"
rm -rf "$STAGE"
mkdir -p "$STAGE"
python3 scripts/archive-source.py "outputs/Bonsai-${VERSION}-Source.zip"
ditto "$APP" "$STAGE/$APP_BUNDLE"
ln -s /Applications "$STAGE/Applications"
cp outputs/Installation.md outputs/Release-Notes.md outputs/Feature-Checklist.md "$STAGE/"
cp LICENSE NOTICE.md "$STAGE/"
# Source is delivered inside the disk image as well as beside it.
cp "outputs/Bonsai-${VERSION}-Source.zip" "$STAGE/"
if [[ "${1:-}" == "--prepare-only" ]]; then
  printf '%s\n' "Prepared $STAGE for Disk Utility → Image from Folder."
  exit 0
fi
hdiutil create -ov -volname 'Bonsai' -srcfolder "$STAGE" -fs HFS+ -format UDZO "outputs/Bonsai-${VERSION}-arm64.dmg"
hdiutil verify "outputs/Bonsai-${VERSION}-arm64.dmg"
shasum -a 256 "outputs/Bonsai-${VERSION}-arm64.dmg" > outputs/DMG-SHA256.txt
