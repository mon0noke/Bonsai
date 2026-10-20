#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/environment.sh
BIN="$PWD/work/build-release/arm64-apple-macosx/release"
APP="$PWD/work/Bonsai Design Studio.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done < <(rg --files Sources/Bonsai -g '*.swift' | rg -v '/BonsaiApp.swift$' | sort)
xcrun swiftc -D BONSAI_DESIGN_EDITOR -larchive -sdk "$BONSAI_SDK" -target arm64-apple-macos14.0 -module-cache-path work/module-cache -I "$BIN/Modules" -I "$BIN/CBonsai.build" "${SOURCES[@]}" scripts/preview-loading.swift "$BIN"/BonsaiCore.build/*.swift.o "$BIN"/CBonsai.build/*.o -framework IOKit -framework Security -o "$APP/Contents/MacOS/LoadingPreview"
cp Resources/InterfaceDesign.json "$APP/Contents/Resources/"
printf '%s\n' "$PWD" > "$APP/Contents/Resources/StudioSourceRoot.txt"
cp -R Resources/Trees "$APP/Contents/Resources/"
cp outputs/Bonsai-Icon.png "$APP/Contents/Resources/BonsaiIcon.png"
python3 - <<'PY'
from pathlib import Path
import plistlib
p=Path('work/Bonsai Design Studio.app/Contents/Info.plist')
p.write_bytes(plistlib.dumps(dict(CFBundleIdentifier='app.bonsai.design-studio',CFBundleExecutable='LoadingPreview',CFBundleName='Bonsai Design Studio',CFBundlePackageType='APPL',LSMinimumSystemVersion='14.0',NSHighResolutionCapable=True)))
PY
codesign --force --sign - "$APP"
printf '%s\n' "$APP"
