#!/bin/bash
# Builds build/Utter.app from the Swift package.
#
# Signing: ad-hoc by default. macOS ties the Accessibility permission to the
# signature, so with ad-hoc signing you have to re-grant it after each rebuild.
# To avoid that, create a self-signed "Code Signing" certificate in Keychain
# Access (Certificate Assistant → Create a Certificate) and build with
#   UTTER_SIGN_IDENTITY="Your Cert Name" ./scripts/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
swift build -c "$CONFIG"

APP="build/Utter.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/Utter" "$APP/Contents/MacOS/Utter"
if [ "$CONFIG" = "release" ]; then
    # Drop debug symbols: they list every source file's absolute path, which would
    # reveal the build machine's user name and folders to anyone with the app.
    strip -S -x "$APP/Contents/MacOS/Utter"
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp sidecar/whisper_server.py "$APP/Contents/Resources/whisper_server.py"
cp scripts/setup-whisper.sh "$APP/Contents/Resources/setup-whisper.sh"

# Prefer an explicit identity, then the "Utter Dev" cert from make-signing-cert.sh, then ad-hoc.
IDENTITY="${UTTER_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] && security find-identity -v -p codesigning | grep -q '"Utter Dev"'; then
    IDENTITY="Utter Dev"
fi
codesign --force --sign "${IDENTITY:--}" --identifier dev.utter.Utter "$APP"

echo "Built $APP (signed with: ${IDENTITY:-ad-hoc signature; run scripts/make-signing-cert.sh once to keep permissions across rebuilds})"
