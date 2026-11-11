# Development

## Requirements

- Apple Silicon Mac, macOS 14+ (macOS 26+ for the on-device cleanup model)
- Swift 6 toolchain. The Command Line Tools are enough (`xcode-select --install`); full Xcode isn't required.

## Build and run

```bash
./scripts/run.sh            # release build → /Applications/Utter.app → launch
./scripts/make-dmg.sh       # release build → build/Utter.dmg (replaces the previous one)
./scripts/setup-whisper.sh  # install Whisper for development (same script the app runs)
swift run UtterChecks       # check UtterCore's logic
```

`run.sh` installs to `/Applications` so the app you test is the one macOS grants permissions to.

## Signing and permissions

macOS ties the Accessibility permission to the app's code signature. An ad-hoc signature changes on every build, so the permission would be lost each time. Create a stable local identity once:

```bash
./scripts/make-signing-cert.sh   # creates a self-signed "Utter Dev" certificate in the login keychain
```

`build.sh` signs with it automatically (or with `UTTER_SIGN_IDENTITY`). After switching signatures, remove Utter from the Accessibility list once and add it again.

Distribution builds need an Apple Developer ID certificate, the hardened runtime and notarization; see [ROADMAP.md](ROADMAP.md).

## Checks

XCTest and swift-testing need full Xcode (they depend on compiler plugins the Command Line Tools don't ship), so `UtterCore` is checked by a plain program, `Sources/UtterChecks/main.swift`. Keep new pure logic in `UtterCore` and add checks there.

## Developer tools (debug builds only)

```bash
swift build
.build/debug/Utter --snapshot /tmp/utter-snaps     # render every screen and island state to PNGs
CONFIG=debug ./scripts/build.sh
open -n -W --stdout /tmp/probe.log build/Utter.app --args --probe-speech clip.aiff
                                                    # play a file into Apple's recognizer, log every callback
```

- Snapshots draw native controls (text fields, toggles, pickers, the sidebar blur) as yellow placeholders; everything else is accurate.
- `--probe-speech` must be launched through `open`. Run directly from a shell, the process is attributed to the terminal and macOS aborts the privacy request.

## Gotchas

- **No `@State`.** On the macOS 27 SDK, SwiftUI's `@State` is a macro whose plugin ships only with full Xcode. View state lives in small `ObservableObject`s with `@StateObject`.
- **Animations.** Never multiply absolute time by a speed that changes (the shape jumps). Integrate phases per frame and ease inputs, as `BlobMotion` does.
- **The notch.** The idle island is exactly the notch's size, so it's invisible and covers nothing. Hover is detected by polling the pointer position, because the pointer disappears under the notch.
- **Whisper on silence.** Whisper invents text such as "Thank you." on silence; the server drops segments it marks as non-speech.

## Project layout

```
Sources/
  UtterCore/        pure logic (checked by UtterChecks)
  UtterChecks/      the checks program
  Utter/
    Pipeline/       transcribers, cleaners, inserter, focus context
    HUD/            notch island, floating pill, liquid orb
    Settings/       settings window and pages
    ...             app state, speech, Whisper sidecar client, commands, theme
sidecar/            whisper_server.py
scripts/            build, run, DMG, icon, signing certificate, Whisper setup
Resources/          Info.plist, app icon
docs/               these documents and screenshots
```
