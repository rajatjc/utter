<p align="center">
  <img src="docs/images/app-icon.png" width="128" alt="Utter app icon">
</p>

<h1 align="center">Utter</h1>

<p align="center">A voice layer for macOS that lives in your MacBook's notch.<br>
Dictate polished text into any app, or tell your Mac what to do.</p>

<p align="center">
  <img src="docs/images/in-use-listening.png" width="420" alt="Listening: the notch opens into a glowing orb and waveform">
  <img src="docs/images/in-use-done.png" width="420" alt="Done: a green check and Inserted 12 words">
</p>

## What it does

- **Dictation.** Hold a key, talk, let go. Utter transcribes with Whisper on your Mac while you talk (so the wait after you let go is about half a second at any length), removes filler words and false starts, fixes punctuation, matches the app you're typing in, and types the result at your cursor.
- **Commands.** Hold another key and say what you want: "open Slack", "remind me at 5 to call Sam", "make this friendlier" (rewrites the selected text), "run the deploy script". Shell commands always wait for you to click **Run**.
- **Private by default.** Speech recognition and dictation cleanup run on your Mac. Nothing is uploaded unless you choose Claude for cleanup or use Command mode.

| | |
|---|---|
| <img src="docs/images/island-controls.png" width="380" alt="Notch controls"> | Rest the pointer under the camera to open the controls. |
| <img src="docs/images/in-use-polishing.png" width="380" alt="Polishing"> | After you release the key, Whisper transcribes and the text is polished. |
| <img src="docs/images/in-use-confirm.png" width="380" alt="Confirm a command"> | Commands that run in Terminal wait for your approval. |

## More screenshots

| | |
|---|---|
| <img src="docs/images/menu.png" width="300" alt="Menu bar panel"> | **Menu bar panel.** Both modes with their shortcuts, recent dictations (click to copy), mute and settings. |
| <img src="docs/images/settings-setup.png" width="380" alt="Get started checklist"> | **Get started.** Four steps: three macOS permissions and the one-time Whisper install. |
| <img src="docs/images/settings-history.png" width="380" alt="History"> | **History.** Everything dictated or asked, stored only on this Mac. |
| <img src="docs/images/floating-pill.png" width="380" alt="Floating pill"> | **Floating pill.** Used automatically on Macs without a notch; drag it anywhere. |

<p align="center"><img src="docs/images/orb-morph.png" width="760" alt="The orb at six moments, quiet (top) and speaking (bottom)"><br>
<em>The orb's shape over time: quiet (top) and while speaking (bottom).</em></p>

## Controls

| Input | Action |
|---|---|
| Hold **Left ⌃ + Left ⌥** | Dictate; release to insert |
| Double-press **Left ⌃ + Left ⌥** | Hands-free dictation; press again to finish |
| Hold **Right ⌘** | Command mode |
| **Esc** | Cancel |

Both shortcuts can be changed in Settings → Shortcuts. Click the menu bar icon for the Utter panel; right-click it for Settings, Mute and Quit.

## Install

| Minimum | Recommended |
|---|---|
| macOS 14, any Mac (Intel or Apple Silicon), 8 GB memory | Apple Silicon, macOS 26 with Apple Intelligence, 16 GB memory |

The app is about 3 MB. Whisper, the speech model, is a separate one-time download of about 3 GB that Utter installs for you; it uses about 1.7 GB of memory while Utter runs. Works on every screen size: in the notch on MacBooks that have one, as a floating pill on other Macs. Full requirements: [INSTALL.md](docs/INSTALL.md#requirements).

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
