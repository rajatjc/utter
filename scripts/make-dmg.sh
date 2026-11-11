#!/bin/bash
# Builds Utter and packages it as build/Utter.dmg (drag Utter into Applications).
#
# Note: this DMG is signed ad-hoc, so on other Macs Gatekeeper will warn that it's
# from an unidentified developer (right-click → Open to get past it). Shipping to
# customers needs an Apple Developer ID certificate plus notarization.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh

STAGING="build/dmg"
rm -rf "$STAGING" build/Utter.dmg
mkdir -p "$STAGING"
cp -R build/Utter.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "Utter" -srcfolder "$STAGING" -ov -format UDZO build/Utter.dmg >/dev/null
rm -rf "$STAGING"
echo "Created build/Utter.dmg"
