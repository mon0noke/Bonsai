#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/environment.sh
xcrun swiftc -sdk "$BONSAI_SDK" -target arm64-apple-macos14.0 -module-cache-path work/module-cache Sources/Bonsai/SettingsScrollView.swift scripts/verify-settings-scroll.swift -o outputs/SettingsScrollVerify
outputs/SettingsScrollVerify
