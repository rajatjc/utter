# 0001: Whisper for transcription, through a local sidecar for now

**Decision.** Final transcripts come from Whisper large-v3-turbo running locally via mlx-whisper, in a Python child process (`sidecar/whisper_server.py`).

**Why.** Apple's built-in recognizer was noticeably worse on accents and jargon and drops words after pauses (see 0002). Whisper transcribes a typical utterance in well under a second on Apple Silicon and keeps audio on the Mac.

**Trade-offs.** A Python environment (~1.3 GB) plus the model (~1.6 GB) must be installed separately, and Intel Macs can't use it. The sidecar is behind the `Transcriber` protocol so it can be replaced by WhisperKit (Swift, Core ML) without touching the rest of the app; that's the plan before selling.

**Security.** The server binds a random localhost port and requires a per-launch token, so other programs on the Mac can't use it.
