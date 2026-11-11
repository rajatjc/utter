# Roadmap

## Before selling

1. **Developer ID signing and notarization.** Join the Apple Developer Program, sign with a Developer ID certificate and the hardened runtime, notarize, and staple the ticket so the app opens without warnings.
2. **Whisper inside the app.** Replace the Python sidecar with WhisperKit (Swift, Core ML) behind the existing `Transcriber` protocol. No Python, no 1.3 GB environment, works for every customer, and the model download moves into the app's own UI.
3. **Licensing and payments.** License keys or a subscription (for example Paddle or Lemon Squeezy, which handle tax), with a trial.
4. **Auto-updates.** Sparkle, or the Mac App Store (which also handles payment, but requires sandboxing; the hotkey and typing features would need rework).
5. **Crash reporting and opt-in analytics.**
6. **A trademark check on the name.** "Utter" is a working name.

## Product

- **Speed:** stream audio to Whisper while the user talks, so text is ready the moment they release.
- **Context:** read the text around the cursor so dictation continues the document naturally; learn vocabulary from corrections.
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
