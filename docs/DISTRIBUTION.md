# Releasing Utter

Utter is free and open source (MIT). A release is a DMG on GitHub Releases. Signing it
with a Developer ID and notarizing it lets people open it without a Gatekeeper warning.

## 1. Sign and notarize

Without this, macOS says Utter "can't be opened" and people have to find **Open Anyway** in System Settings.

1. Join the [Apple Developer Program](https://developer.apple.com/programs/) (US$99 a year).
2. In Keychain Access or on developer.apple.com, create a **Developer ID Application** certificate and install it in your login keychain. Check that it's there:
   ```bash
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```
3. Create an app-specific password at [account.apple.com](https://account.apple.com) (Sign-In and Security → App-Specific Passwords), then save notary credentials once:
   ```bash
   xcrun notarytool store-credentials utter-notary \
       --apple-id you@example.com --team-id TEAMID --password xxxx-xxxx-xxxx-xxxx
   ```
4. Build, sign, notarize and staple:
   ```bash
   UTTER_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/make-dmg.sh
   ./scripts/notarize.sh
   ```

With a Developer ID identity, `build.sh` turns on the hardened runtime and applies `Resources/Utter.entitlements` (microphone and Apple events), as notarization requires. `notarize.sh` refuses a DMG that isn't signed that way, then submits it, waits, staples the ticket and checks it with Gatekeeper. Notarytool ships with the Command Line Tools; full Xcode isn't needed.

People who used a self-signed build need to turn Accessibility on again once after switching to the Developer ID build, because macOS ties that permission to the signature.

## 2. Publish on GitHub Releases

1. Build the DMG: `./scripts/make-dmg.sh` (notarized as above, or self-signed without a Developer ID).
2. Create the release and attach the DMG:
   ```bash
   gh release create v0.1.0 build/Utter.dmg --title "Utter 0.1.0" --notes-file release-notes.md
   ```

If the build isn't notarized, say so in the release notes, with the one-time step: open the
DMG, drag Utter to Applications, try to open it, then **System Settings → Privacy &
Security → Open Anyway**.
