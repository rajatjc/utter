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

Release builds are universal (`arm64` + `x86_64`) and have debug symbols stripped; debug builds are Apple Silicon only. To check the Intel slice on an Apple Silicon Mac, build a universal debug binary and run it under Rosetta:

```bash
swift build --arch arm64 --arch x86_64
arch -x86_64 .build/out/Products/Debug/Utter --snapshot /tmp/utter-intel
```

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
                                                    # (sizes-*.png: the island at three notch widths;
                                                    # frames/: a dictation as 30 fps frames)
./scripts/make-demo-video.sh /tmp/utter-snaps/frames docs/images
                                                    # frames → docs/images/demo.gif (README) and demo.mp4
CONFIG=debug ./scripts/build.sh
.build/debug/Utter --probe-parakeet clip.wav        # download/load Parakeet, transcribe a 16 kHz mono WAV, time it
open -n -W --stdout /tmp/probe.log build/Utter.app --args --probe-speech clip.aiff
                                                    # play a file into Apple's recognizer, log every callback
.build/debug/Utter --probe-whisper-stream clip.wav  # play a 16 kHz mono WAV into streaming Whisper in real time;
                                                    # compares the wait and text with transcribing it all at once
.build/debug/Utter --orb-bench both 20              # the listening orb and waveform (or `orb`, `wave`) in a window
                                                    # with a simulated voice for 20 s; measure the process's CPU
```

To measure the animation's real cost, build optimized with the debug tools kept, then sample the CPU while the bench runs:

```bash
swift build -c release -Xswiftc -DDEBUG --build-path /tmp/utter-bench
/tmp/utter-bench/release/Utter --orb-bench both 22 & sleep 4; for i in $(seq 15); do ps -o %cpu= -p $!; sleep 1; done
```

At 30 fps the orb and waveform together use about 10% of one core while talking.

- Snapshots draw native controls (text fields, toggles, pickers, the sidebar blur) as yellow placeholders; everything else is accurate.
- `--probe-speech` must be launched through `open`. Run directly from a shell, the process is attributed to the terminal and macOS aborts the privacy request.

## Releasing

Signing with a Developer ID, notarizing and license keys: [DISTRIBUTION.md](DISTRIBUTION.md). Issue a key for yourself so the trial never blocks you while developing:

```bash
swift scripts/license.swift issue --name "Your Name" --email you@example.com
```

Paste it in Settings → License.

## Gotchas

- **No `@State`.** On the macOS 27 SDK, SwiftUI's `@State` is a macro whose plugin ships only with full Xcode. View state lives in small `ObservableObject`s with `@StateObject`.
- **Animations.** Never multiply absolute time by a speed that changes (the shape jumps). Integrate phases per frame and ease inputs, as `BlobMotion` does. Cap `TimelineView`s at 30 fps, keep blurs few (each is an offscreen pass every frame), and honour Reduce Motion (`accessibilityReduceMotion`).
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
