# Roadmap

## Before selling

Done in code; each needs an account (see [DISTRIBUTION.md](DISTRIBUTION.md)): Developer ID signing and notarization scripts, a built-in speech model (Parakeet, no Python), offline license keys with a 14-day trial, and a webhook Worker that emails keys.

1. **Accounts.** Apple Developer Program, a Lemon Squeezy store, Resend and Cloudflare. Then point `LicenseManager.purchaseURL` at the checkout.
2. **Real-world testing** of the new features: voice edits, cursor fitting and correction learning in Mail, Slack, Notes, browsers and code editors; Parakeet on M1 and 8 GB Macs, and on Intel.
3. **Auto-updates.** Sparkle, or the Mac App Store (which also handles payment, but requires sandboxing; the hotkey and typing features would need rework).
4. **Crash reporting and opt-in analytics.**
5. **A trademark check on the name.** "Utter" is a working name.

## Product

- **Parakeet Ultra:** FluidAudio's newer Parakeet variant claims better accuracy at the same speed; compare it on real recordings.
- **Streaming Parakeet** for live text while talking, replacing Apple's recognizer for the preview.
- **Commands without an API key:** run the command loop on Apple's on-device model (its tool-calling API needs full Xcode to compile).
- **Unified key:** one hotkey, with the model deciding whether the user is dictating or commanding.
- **Deeper Mac control:** Accessibility-based actions (click buttons by name, read the screen) and connectors for calendar, email and task tools.
- **Hosted option:** a backend so customers can use Claude features without their own API key, billed by usage.

## Known gaps

- Pasting doesn't work in a few apps that block synthesized keystrokes (some terminals, remote desktops).
- Hotkeys are limited to modifier chords (no letter keys or Fn).
- Reminders, Notes and dark mode ask for Automation permission the first time each is used.
- In hands-free mode the ✓ and ✕ buttons widen the island while listening.
- Command mode hasn't been tested end to end against the live API.
