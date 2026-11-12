# Roadmap

## Next

Done in code (see [DISTRIBUTION.md](DISTRIBUTION.md)): Developer ID signing and notarization scripts, and a built-in speech model (Parakeet, no Python).

1. **A downloadable release.** A notarized DMG on GitHub Releases needs an Apple Developer Program membership; until then, a self-signed DMG works with one extra step for users.
2. **Real-world testing** of the new features: voice edits, cursor fitting and correction learning in Mail, Slack, Notes, browsers and code editors; Parakeet on M1 and 8 GB Macs, and on Intel.
3. **Auto-updates.** Sparkle, pointed at GitHub Releases.
4. **Crash reporting and opt-in analytics.**
5. **A trademark check on the name.** "Utter" is a working name.

## Product

- **Parakeet Ultra:** FluidAudio's newer Parakeet variant claims better accuracy at the same speed; compare it on real recordings.
- **Streaming Parakeet** for live text while talking, replacing Apple's recognizer for the preview.
- **Commands without an API key:** run the command loop on Apple's on-device model (its tool-calling API needs full Xcode to compile).
- **Unified key:** one hotkey, with the model deciding whether the user is dictating or commanding.
- **Deeper Mac control:** Accessibility-based actions (click buttons by name, read the screen) and connectors for calendar, email and task tools.

## Known gaps

- Pasting doesn't work in a few apps that block synthesized keystrokes (some terminals, remote desktops).
- Hotkeys are limited to modifier chords (no letter keys or Fn).
- Reminders, Notes and dark mode ask for Automation permission the first time each is used.
- In hands-free mode the ✓ and ✕ buttons widen the island while listening.
- Command mode hasn't been tested end to end against the live API.
