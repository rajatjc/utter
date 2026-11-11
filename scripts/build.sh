#!/bin/bash
# Builds build/Utter.app from the Swift package.
#
# Signing: ad-hoc by default. macOS ties the Accessibility permission to the
# signature, so with ad-hoc signing you have to re-grant it after each rebuild.
# To avoid that, create a self-signed "Code Signing" certificate in Keychain
# Access (Certificate Assistant → Create a Certificate) and build with
#   UTTER_SIGN_IDENTITY="Your Cert Name" ./scripts/build.sh
#
# For customers, sign with your Developer ID certificate, which also turns on
# the hardened runtime, then notarize:
#   UTTER_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/make-dmg.sh
#   ./scripts/notarize.sh
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
# Release builds are universal so the app also opens on Intel Macs (where it uses
# Apple's recognizer: Whisper via MLX and Apple's on-device model need Apple Silicon).
ARCH_FLAGS=()
[ "$CONFIG" = "release" ] && ARCH_FLAGS=(--arch arm64 --arch x86_64)
swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

APP="build/Utter.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Utter" "$APP/Contents/MacOS/Utter"
if [ "$CONFIG" = "release" ]; then
    # Drop debug symbols: they list every source file's absolute path, which would
    # reveal the build machine's user name and folders to anyone with the app.
    strip -S -x "$APP/Contents/MacOS/Utter"
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp sidecar/whisper_server.py "$APP/Contents/Resources/whisper_server.py"
cp scripts/setup-whisper.sh "$APP/Contents/Resources/setup-whisper.sh"
# Apache-2.0 asks for the license text to travel with the binary.
mkdir -p "$APP/Contents/Resources/Licenses"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/Licenses/THIRD_PARTY_NOTICES.md"
cp .build/checkouts/FluidAudio/LICENSE "$APP/Contents/Resources/Licenses/FluidAudio-LICENSE.txt"

# Prefer an explicit identity, then the "Utter Dev" cert from make-signing-cert.sh, then ad-hoc.
IDENTITY="${UTTER_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] && security find-identity -v -p codesigning | grep -q '"Utter Dev"'; then
    IDENTITY="Utter Dev"
fi
if [[ "$IDENTITY" == "Developer ID Application"* ]]; then
    # Distribution: hardened runtime, entitlements and a secure timestamp, as
    # notarization requires. Then run scripts/notarize.sh.
    codesign --force --sign "$IDENTITY" --identifier dev.utter.Utter \
        --options runtime --timestamp --entitlements Resources/Utter.entitlements "$APP"
else
    codesign --force --sign "${IDENTITY:--}" --identifier dev.utter.Utter "$APP"
fi

echo "Built $APP (signed with: ${IDENTITY:-ad-hoc signature; run scripts/make-signing-cert.sh once to keep permissions across rebuilds})"
