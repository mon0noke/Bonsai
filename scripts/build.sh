#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/environment.sh
mkdir -p work outputs
python3 scripts/sync-harness.py
CONFIG="${1:-release}"
case "$CONFIG" in debug|release) ;; *) echo "Use debug or release" >&2; exit 2;; esac
if [[ "${2:-}" == "--clean" ]]; then rm -rf "$PWD/work/build-$CONFIG"; fi
swift build --build-system native --disable-sandbox --sdk "$BONSAI_SDK" --arch arm64 --cache-path work/package-cache --scratch-path "work/build-$CONFIG" -c "$CONFIG"
BIN=$(swift build --build-system native --disable-sandbox --sdk "$BONSAI_SDK" --arch arm64 --cache-path work/package-cache --scratch-path "work/build-$CONFIG" -c "$CONFIG" --show-bin-path)
APP="$PWD/outputs/${BONSAI_APP_NAME:-Bonsai}.app"
if [[ -d "$APP" ]]; then mv "$APP" "work/Bonsai-previous-$(date +%s).bundle-backup"; fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Bonsai" "$APP/Contents/MacOS/Bonsai"
if [[ "${BONSAI_SIGN_IDENTITY:--}" != "-" ]]; then
  mkdir -p "$APP/Contents/Frameworks"
  cp -R Vendor/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$APP/Contents/Frameworks/"
  install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Bonsai"
  cp Vendor/Sparkle-LICENSE "$APP/Contents/Resources/"
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/InterfaceDesign.json "$APP/Contents/Resources/"
cp Resources/PrivacyInfo.xcprivacy LICENSE "$APP/Contents/Resources/"

cp -R Resources/MaintenanceBackend "$APP/Contents/Resources/MaintenanceBackend"
mkdir -p "$APP/Contents/Helpers"
cp Vendor/mas "$APP/Contents/Helpers/mas"
cp "$BIN/BonsaiStoreUpdate" "$APP/Contents/Helpers/"
if [[ "$CONFIG" == "release" ]]; then xcrun strip -S "$APP/Contents/Helpers/BonsaiStoreUpdate"; fi
codesign --force --options runtime --sign "${BONSAI_SIGN_IDENTITY:--}" "$APP/Contents/Helpers/BonsaiStoreUpdate"
cp Vendor/libarchive-LICENSE "$APP/Contents/Resources/"
cp Vendor/mas-LICENSE "$APP/Contents/Resources/"
cp "$BIN/BonsaiMaintenanceTrash" "$APP/Contents/Helpers/"
if [[ "$CONFIG" == "release" ]]; then xcrun strip -S "$APP/Contents/Helpers/BonsaiMaintenanceTrash"; fi
codesign --force --options runtime --sign "${BONSAI_SIGN_IDENTITY:--}" "$APP/Contents/Helpers/BonsaiMaintenanceTrash"
cp -R Resources/ProtectionBackend "$APP/Contents/Resources/ProtectionBackend"
cp -R Resources/Trees "$APP/Contents/Resources/Trees"
cp Resources/BonsaiIcon-Artwork.json "$APP/Contents/Resources/"
cp Resources/THIRD-PARTY-NOTICES.md "$APP/Contents/Resources/"
xcrun swift -sdk "$BONSAI_SDK" scripts/icon.swift work/Bonsai.iconset
python3 scripts/icns.py work/Bonsai.iconset "$APP/Contents/Resources/Bonsai.icns"
cp work/Bonsai.iconset/icon_512x512@2x.png outputs/Bonsai-Icon.png
cp outputs/Bonsai-Icon.png "$APP/Contents/Resources/BonsaiIcon.png"
printf 'APPL????' > "$APP/Contents/PkgInfo"
# Keep debug information in build products, outside the distributed release app.
if [[ "$CONFIG" == "release" ]]; then xcrun strip -S "$APP/Contents/MacOS/Bonsai"; fi
# Local development path defaults to an ad-hoc signature, with hardened runtime.
if [[ "${BONSAI_SIGN_IDENTITY:--}" == "-" ]]; then
  codesign --force --options runtime --sign - "$APP"
else
  # Re-sign nested Sparkle components with the distribution team, inside out.
  python3 scripts/sign-framework.py "$APP/Contents/Frameworks/Sparkle.framework" "$BONSAI_SIGN_IDENTITY"
  codesign --force --options runtime --timestamp --sign "$BONSAI_SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"
cp "$BIN/BonsaiVerify" outputs/BonsaiVerify
printf '%s\n' "$APP"
