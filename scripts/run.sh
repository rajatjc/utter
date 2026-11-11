#!/bin/bash
# Rebuilds Utter, installs it to /Applications, and relaunches it from there.
set -euo pipefail
cd "$(dirname "$0")/.."
pkill -x Utter 2>/dev/null || true
./scripts/build.sh

DEST="/Applications/Utter.app"
rm -rf "$DEST"
cp -R build/Utter.app "$DEST"
echo "Installed $DEST"
open "$DEST"
