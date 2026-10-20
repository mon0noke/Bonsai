#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/environment.sh
mkdir -p work outputs
xcrun swiftc -sdk "$BONSAI_SDK" -module-cache-path work/module-cache Sources/Bonsai/NatureScene.swift Sources/Bonsai/BotanicalLeaf.swift Sources/Bonsai/TreeWindDynamics.swift Sources/Bonsai/LeafSweepDynamics.swift Sources/Bonsai/LeafPageTransition.swift scripts/verify-page-motion.swift -o outputs/PageMotionVerify
./outputs/PageMotionVerify
