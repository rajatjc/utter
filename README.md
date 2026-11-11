<p align="center">
  <img src="docs/images/app-icon.png" width="128" alt="Utter app icon">
</p>

<h1 align="center">Utter</h1>

<p align="center">A voice layer for macOS that lives in your MacBook's notch.<br>
Dictate polished text into any app, or tell your Mac what to do.</p>

<p align="center">
  <img src="docs/images/island-listening.png" width="380" alt="Listening">
  <img src="docs/images/island-done.png" width="380" alt="Done">
</p>

## What it does

- **Dictation.** Hold a key, talk, let go. Utter transcribes with Whisper on your Mac, removes filler words and false starts, fixes punctuation, matches the app you're typing in, and types the result at your cursor.
- **Commands.** Hold another key and say what you want: "open Slack", "remind me at 5 to call Sam", "make this friendlier" (rewrites the selected text), "run the deploy script". Shell commands always wait for you to click **Run**.
- **Private by default.** Speech recognition and dictation cleanup run on your Mac. Nothing is uploaded unless you choose Claude for cleanup or use Command mode.

| | |
|---|---|
| <img src="docs/images/island-controls.png" width="380" alt="Notch controls"> | Rest the pointer under the camera to open the controls. |
| <img src="docs/images/island-polishing.png" width="380" alt="Polishing"> | After you release the key, Whisper transcribes and the text is polished. |
| <img src="docs/images/island-confirm-command.png" width="380" alt="Confirm a command"> | Commands that run in Terminal wait for your approval. |

## Controls

| Input | Action |
|---|---|
| Hold **Left ⌃ + Left ⌥** | Dictate; release to insert |
| Double-press **Left ⌃ + Left ⌥** | Hands-free dictation; press again to finish |
| Hold **Right ⌘** | Command mode |
| **Esc** | Cancel |

Both shortcuts can be changed in Settings → Shortcuts.

## Install

You need an Apple Silicon Mac with macOS 14 or later. The app itself is about 3 MB; the Whisper speech model is a separate one-time download of about 3 GB that Utter installs for you.

1. Open `Utter.dmg` and drag **Utter** into **Applications**.
2. Open Utter and follow the **Get started** checklist: Microphone, Speech Recognition and Accessibility permissions, then **Install** Whisper.
3. Hold **Left ⌃ + Left ⌥** in any text field and talk.

Full instructions, including what gets downloaded where and how to uninstall: **[docs/INSTALL.md](docs/INSTALL.md)**.

## How it works

```mermaid
flowchart LR
    K[Hotkey or notch click] --> M[Microphone capture]
    M --> W[Whisper<br/>local model]
    W --> C[Cleanup<br/>Apple on-device model]
    C --> I[Type into the<br/>focused app]
    M -. Command mode .-> A[Claude tool loop] --> X[Mac actions]
```

Details: **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**.

## Documentation

| Document | For |
|---|---|
| [INSTALL.md](docs/INSTALL.md) | Installing on a new Mac, Whisper setup, troubleshooting, uninstalling |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Components, data flow, privacy and security |
| [DEVELOPMENT.md](docs/DEVELOPMENT.md) | Building from source, signing, checks, developer tools |
| [ROADMAP.md](docs/ROADMAP.md) | Known gaps and what's next |
| [decisions/](docs/decisions/) | Why things are the way they are |

## License

Copyright © 2026 The Utter authors. All rights reserved. The source is published for reference only; see [LICENSE](LICENSE). Third-party components are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
