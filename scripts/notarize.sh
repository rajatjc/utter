#!/bin/bash
# Sends build/Utter.dmg to Apple's notary service, waits for the verdict, and
# staples the ticket so the DMG opens without warnings, even offline.
#
# Needs (once):
#   1. An Apple Developer Program membership and a "Developer ID Application"
#      certificate in your login keychain.
#   2. Saved notary credentials, using an app-specific password from
#      account.apple.com (Sign-In and Security → App-Specific Passwords):
#        xcrun notarytool store-credentials utter-notary \
#            --apple-id you@example.com --team-id TEAMID --password xxxx-xxxx-xxxx-xxxx
#
# Then:
#   UTTER_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/make-dmg.sh
#   ./scripts/notarize.sh
set -euo pipefail
cd "$(dirname "$0")/.."

DMG="build/Utter.dmg"
PROFILE="${UTTER_NOTARY_PROFILE:-utter-notary}"
[ -f "$DMG" ] || { echo "No $DMG. Run scripts/make-dmg.sh first."; exit 1; }

# Refuse early if the app inside isn't signed for distribution.
MOUNT="$(mktemp -d)"
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT" >/dev/null
SIGNED_BY="$(codesign -dvv "$MOUNT/Utter.app" 2>&1 | grep -m1 '^Authority=' || true)"
FLAGS="$(codesign -dvv "$MOUNT/Utter.app" 2>&1 | grep -m1 'flags=' || true)"
hdiutil detach "$MOUNT" >/dev/null
if [[ "$SIGNED_BY" != "Authority=Developer ID Application"* || "$FLAGS" != *runtime* ]]; then
    echo "Utter.app isn't signed with a Developer ID certificate and the hardened runtime."
    echo "Rebuild with UTTER_SIGN_IDENTITY=\"Developer ID Application: …\" ./scripts/make-dmg.sh"
    exit 1
fi

echo "Submitting $DMG (this usually takes a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"
echo "Notarized and stapled: $DMG"
