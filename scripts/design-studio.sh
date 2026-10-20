#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Build the usual modules if this is a fresh workspace; the app is not installed.
if [[ ! -d work/build-release/arm64-apple-macosx/release/BonsaiCore.build ]]; then
    bash scripts/build.sh release
fi
bash scripts/preview-loading.sh
