#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/environment.sh
xcrun swiftc -sdk "$BONSAI_SDK" -target arm64-apple-macos14.0 -module-cache-path work/module-cache Sources/Bonsai/DesignPreferences.swift scripts/verify-design-production.swift -o outputs/ProductionDesignVerify
outputs/ProductionDesignVerify
