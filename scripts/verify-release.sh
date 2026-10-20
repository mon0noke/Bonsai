#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PWD/outputs/${BONSAI_APP_NAME:-Bonsai}.app/Contents/Info.plist")
DMG="$PWD/outputs/Bonsai-${VERSION}-arm64.dmg"
shasum -a 256 "$DMG"
hdiutil verify "$DMG"
if [[ "${1:-}" == "--mounted" ]]; then
  MOUNT="${2:?Provide the already-mounted Bonsai volume path}"
else
  MOUNT="$PWD/work/Bonsai-Mounted"
  mkdir -p "$MOUNT"
  hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$DMG"
  trap 'hdiutil detach "$MOUNT"' EXIT
fi
python3 - "$MOUNT" <<'READONLY'
import os,sys
assert os.statvfs(sys.argv[1]).f_flag & os.ST_RDONLY, 'Volume must be read-only'
print('Read-only volume: verified')
READONLY
APP="$MOUNT/${BONSAI_APP_NAME:-Bonsai}.app"
[[ -L "$MOUNT/Applications" && "$(readlink "$MOUNT/Applications")" == /Applications ]]
lipo -archs "$APP/Contents/MacOS/Bonsai"
file "$APP/Contents/MacOS/Bonsai"
plutil -lint "$APP/Contents/Info.plist" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=4 "$APP"
otool -l "$APP/Contents/MacOS/Bonsai" | awk '/LC_BUILD_VERSION/{n=8} n>0{print;n--}'
printf '%s\n' 'Bundle inspection passed. Test launch, window interactions, quit and eject separately in Finder.'
