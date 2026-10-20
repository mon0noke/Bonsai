#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/environment.sh
CONFIG="${1:-release}"
BIN="$PWD/work/build-$CONFIG/arm64-apple-macosx/$CONFIG"
xcrun swiftc -larchive -sdk "$BONSAI_SDK" -target arm64-apple-macos14.0 -module-cache-path work/module-cache -I "$BIN/Modules" -I "$BIN/CBonsai.build" Sources/Bonsai/SoftwareStore.swift scripts/verify-software-state.swift "$BIN"/BonsaiCore.build/*.swift.o "$BIN"/CBonsai.build/*.o -framework IOKit -framework Security -o outputs/SoftwareStateVerify
./outputs/SoftwareStateVerify
