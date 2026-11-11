#!/bin/bash
# Builds Utter and packages it as build/Utter.dmg (drag Utter into Applications).
#
# Without a Developer ID certificate the app is self-signed, so on other Macs
# Gatekeeper warns that it's from an unidentified developer (right-click → Open
# to get past it). For customers: set UTTER_SIGN_IDENTITY to your Developer ID
# certificate, run this, then scripts/notarize.sh (see docs/DISTRIBUTION.md).
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
if [[ "${UTTER_SIGN_IDENTITY:-}" == "Developer ID Application"* ]]; then
    codesign --force --sign "$UTTER_SIGN_IDENTITY" --timestamp build/Utter.dmg
fi
echo "Created build/Utter.dmg"
