# Installing Utter on a new Mac

## Requirements

### Summary

| | Minimum | Recommended |
|---|---|---|
| Mac | Any Mac that runs macOS 14, Intel or Apple Silicon | Apple Silicon (M1 or later) |
| macOS | 14 Sonoma | 26 or later, with Apple Intelligence turned on |
| Memory (RAM) | 8 GB | 16 GB or more |
| Free disk space | 10 MB (Intel, no Whisper) | 4 GB (app, Whisper and its model, plus headroom) |
| Internet | Only for the one-time Whisper download | |

### What each part needs

| Part | Memory while running | Disk | Needs |
|---|---|---|---|
| Utter app | about 110 MB | about 3 MB | macOS 14+ (universal: runs on Intel and Apple Silicon) |
| Whisper speech recognition | about 1.7 GB, loaded for as long as Utter runs | about 2.9 GB: Python packages 1.3 GB in `~/Library/Application Support/Utter`, model 1.6 GB in `~/.cache/huggingface` | Apple Silicon, Python 3.10+ (`brew install python`), one-time download |
| On-device cleanup (fillers, punctuation, tone) | managed by macOS | Apple Intelligence's own models, downloaded by macOS | macOS 26+, Apple Silicon, Apple Intelligence turned on |
| Apple's built-in recognizer (fallback) | small | none | Siri & Dictation turned on |
| Claude (optional) | none extra | none | An Anthropic API key and an internet connection |

Utter's own footprint with Whisper is about **1.8 GB of memory and 3 GB of disk**. On an 8 GB Mac that's a noticeable share of memory, so 16 GB is recommended if you keep many apps open. Utter hasn't been tested on an 8 GB Mac yet.

### What works on which Mac

| | Apple Silicon, macOS 26+ | Apple Silicon, macOS 14–15 | Intel Mac |
|---|---|---|---|
| Speech recognition | Whisper | Whisper | Apple's built-in recognizer |
| Cleanup | On-device model | Basic (fillers, capitalization, snippets), or Claude | Basic, or Claude |
| Command mode | With an API key | With an API key | With an API key |

### Screens and displays

Utter works on every screen size and display scaling, including built-in, external and multiple displays:

- **MacBooks with a notch** (14" and 16" MacBook Pro from 2021, MacBook Air from 2022): Utter lives in the notch. Its size and position are read from macOS, so it fits at any scaling ("Larger Text" through "More Space") and wherever the MacBook sits in a multi-display arrangement.
- **Macs without a notch** (iMac, Mac mini, Mac Studio, Mac Pro, older MacBooks, or a MacBook with its lid closed): Utter shows a floating pill at the top of the screen, which you can drag anywhere. It switches automatically when displays change.

### Speed

Utter transcribes while you talk: each time you pause naturally, the audio so far is sent to Whisper in the background. When you let go, only the last few seconds are left, so the wait is about the same however long you talk. Measured on an M3 Pro with Whisper large-v3-turbo:

| Dictation | Wait after you let go |
|---|---|
| 7 seconds | about 0.7 s |
| 30 seconds | about 0.6 s (1.1 s without streaming) |
| 70 seconds | about 0.7 s (2.8 s without streaming) |

On-device cleanup adds about a second. Older or base-model chips (M1, M2) will be slower; if Whisper can't keep up while you talk, the remainder is simply transcribed when you let go.

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
| Wrong words, or text in the wrong language | Settings → AI & dictation → Speech language: pick yours instead of System default |
| "Didn't catch that" | Utter heard no speech (only silence or background noise), so nothing was typed. Speak a little closer to the microphone |
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
