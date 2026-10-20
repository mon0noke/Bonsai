#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/environment.sh
BIN="$PWD/work/build-release/arm64-apple-macosx/release"
xcrun swiftc -larchive -parse-as-library -sdk "$BONSAI_SDK" -target arm64-apple-macos14.0 -module-cache-path work/module-cache -I "$BIN/Modules" -I "$BIN/CBonsai.build" scripts/verify-maintenance-backend.swift "$BIN"/BonsaiCore.build/*.swift.o "$BIN"/CBonsai.build/*.o -framework IOKit -framework Security -o outputs/MaintenanceBackendVerify
./outputs/MaintenanceBackendVerify
