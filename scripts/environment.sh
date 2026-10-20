#!/bin/bash
# Source from repository root. All build caches stay in the workspace.
export CLANG_MODULE_CACHE_PATH="$PWD/work/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/work/module-cache"
BONSAI_SDK="${BONSAI_SDK:-$(xcrun --show-sdk-path)}"
# Some prerelease macOS 27 CLT installations lack SwiftUIMacros.
if [[ "$BONSAI_SDK" == *27* && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
  BONSAI_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
export BONSAI_SDK
