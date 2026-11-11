# Installing Utter on a new Mac

## Requirements

| | Required for | Notes |
|---|---|---|
| macOS 14 Sonoma or later | Everything | |
| Apple Silicon (M1 or later) | Whisper speech recognition | Intel Macs fall back to Apple's built-in recognizer |
| Python 3.10 or later | Installing Whisper | macOS's own Python (3.9) is too old; `brew install python` provides one |
| About 3 GB of free disk space | Whisper | Python packages (~1.3 GB) and the model (~1.6 GB) |
| About 2 GB of free memory | Whisper | The model stays loaded while Utter runs |
| macOS 26 with Apple Intelligence turned on | On-device cleanup | Without it, dictation still works with basic cleanup |
| Anthropic API key (optional) | Command mode, or Claude as the cleanup engine | console.anthropic.com |

## 1. Install the app

1. Open `Utter.dmg` and drag **Utter** onto the **Applications** folder.
2. Open Utter from Applications.
   - Until Utter is signed with an Apple Developer ID and notarized, macOS says it "can't be opened because Apple cannot check it for malicious software". Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to the Utter message. You only need to do this once.

Utter lives in the menu bar and the notch, so there's no Dock icon. The **Get started** window opens automatically the first time.

## 2. Grant permissions

The **Get started** checklist walks through these:

| Permission | Why | Where |
|---|---|---|
| Microphone | Hear you while you hold the key | Prompted on first launch |
| Speech Recognition | Apple's recognizer (fallback and optional live preview) | Prompted on first launch |
| Accessibility | Notice the hotkeys and type into other apps | System Settings → Privacy & Security → Accessibility → turn on **Utter** |

Utter notices the Accessibility switch within a couple of seconds; no restart is needed. Until it's on, dictated text is copied to the clipboard instead of typed.

If speech recognition reports that it's unavailable, turn on **Siri & Dictation** in System Settings.

## 3. Install Whisper

The app download is small (about 3 MB) because the speech model isn't inside it. Click **Install** in step 4 of **Get started**, or **Install Whisper** in **Settings → AI & dictation**. Utter then:

1. Finds Python 3.10 or later (Homebrew's `/opt/homebrew/bin/python3` first).
2. Creates a private Python environment in `~/Library/Application Support/Utter/whisper-env` and installs [mlx-whisper](https://github.com/ml-explore/mlx-examples/tree/main/whisper) and its dependencies (~1.3 GB).
3. Downloads the Whisper large-v3-turbo model (~1.6 GB) from Hugging Face into `~/.cache/huggingface/hub`.
4. Starts Whisper. The first start takes a few seconds; after that it stays loaded.

This is a one-time download of about 3 GB, and it takes a few minutes on a fast connection. Progress shows in **Settings → AI & dictation**.

If the installer says Python is missing, install it and click **Install** again:

```bash
# Install Homebrew first if you don't have it: https://brew.sh
brew install python
```

The same installer can be run from a terminal, which shows full output:

```bash
"/Applications/Utter.app/Contents/Resources/setup-whisper.sh"
```

## 4. Optional: Claude API key

Dictation needs no account. To use Command mode (or Claude as the cleanup engine), paste an Anthropic API key into **Settings → AI & dictation**. It's stored in your login Keychain.

## 5. Try it

Click into any text field, hold **Left ⌃ + Left ⌥**, say something, and let go. The notch shows a glowing orb while you talk, then "Polishing", then "Inserted N words".

## Troubleshooting

| Symptom | Fix |
|---|---|
| Nothing happens when holding the hotkey | Accessibility isn't on, or Utter is muted (menu bar → Unmute) |
| Text is copied but not typed | Accessibility isn't on |
| "Whisper isn't installed" | Settings → AI & dictation → Install Whisper |
| Whisper fails to start | Settings → AI & dictation → Restart; the log is `~/Library/Application Support/Utter/whisper.log` |
| Speech recognition unavailable | System Settings → Siri & Dictation → turn on |
| A few apps ignore the text | Utter pastes with ⌘V; some terminals and remote desktops block synthesized keystrokes |

## Uninstalling

1. Quit Utter from the menu bar and delete it from Applications.
2. Delete the Whisper environment, settings and history:
   ```bash
   rm -rf "$HOME/Library/Application Support/Utter"
   defaults delete dev.utter.Utter
   ```
3. Optionally delete the Whisper model (shared with other apps that use Hugging Face):
   ```bash
   rm -rf ~/.cache/huggingface/hub/models--mlx-community--whisper-large-v3-turbo
   ```
4. Remove Utter from System Settings → Privacy & Security → Accessibility.
