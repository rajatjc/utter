# 0007: A built-in speech model (Parakeet) as the default

**Decision.** New installs use NVIDIA Parakeet TDT 0.6B v3, run on the Neural Engine through [FluidAudio](https://github.com/FluidInference/FluidAudio) (Swift, Core ML) inside the app. Whisper stays available, and Macs that already have it set up keep using it.

**Why.** Whisper needed Python, a 1.3 GB environment and a 1.6 GB model, which is too much to ask of a buyer. Parakeet is one 471 MB download with no other software, and it's as fast without streaming as Whisper is with it.

| Measured on an M3 Pro | Parakeet v3 | Whisper turbo, streamed |
|---|---|---|
| Wait after a 70 s dictation | 0.64 s | about 0.7 s |
| Wait after a 19 s dictation | 0.28 s | about 0.6 s |
| Memory | about 200 MB | about 1.7 GB |
| Download | 471 MB | about 2.9 GB |
| Load from disk | 0.2 s | a few seconds |

**What was considered.** WhisperKit keeps the Whisper model but is slower than Parakeet on the Neural Engine and still a large download. Parakeet's transcripts of the test recordings were as accurate as Whisper's.

**Trade-offs.** Parakeet v3 covers English and 24 other European languages; Whisper covers about 100, so it stays as the choice for other languages. The first load after download takes about 15 seconds while Core ML prepares the model. FluidAudio's text normalization is turned off to avoid an 87 MB prebuilt binary.

**Checked by** `Utter --probe-parakeet <wav>` (debug builds).
