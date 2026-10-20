#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/environment.sh
swift test --build-system native --disable-sandbox --sdk "$BONSAI_SDK" --arch arm64 --cache-path work/package-cache --scratch-path work/build-tests "$@"
