# 0005: Insert text by pasting

**Decision.** Text is inserted by putting it on the pasteboard, sending ⌘V, then restoring the user's previous clipboard. The pasteboard entry is marked transient so clipboard managers skip it.

**Why.** It works in nearly every app, handles any length and Unicode instantly, and replaces the selection (which command-mode rewrites rely on). Typing character by character is slow and breaks on keyboard layouts and autocomplete.

**Trade-offs.** A few apps block synthesized ⌘V (some terminals, remote desktops). Without Accessibility, keystrokes can't be sent, so the text is left on the clipboard with a message.
