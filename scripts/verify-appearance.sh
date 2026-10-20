#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/environment.sh
mkdir -p work outputs
xcrun swiftc -sdk "$BONSAI_SDK" -module-cache-path work/module-cache Sources/Bonsai/Appearance.swift Sources/Bonsai/HandCursor.swift scripts/verify-appearance.swift -o outputs/AppearanceVerify
./outputs/AppearanceVerify
