#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/environment.sh
BIN="$PWD/work/build-release/arm64-apple-macosx/release"
SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done < <(rg --files Sources/Bonsai -g '*.swift' | rg -v '/BonsaiApp.swift$' | sort)
xcrun swiftc -D BONSAI_DESIGN_EDITOR -larchive -sdk "$BONSAI_SDK" -target arm64-apple-macos14.0 -module-cache-path work/module-cache -I "$BIN/Modules" -I "$BIN/CBonsai.build" "${SOURCES[@]}" scripts/verify-design.swift "$BIN"/BonsaiCore.build/*.swift.o "$BIN"/CBonsai.build/*.o -framework IOKit -framework Security -o outputs/DesignVerify
outputs/DesignVerify
