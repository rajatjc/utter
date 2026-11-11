# 0006: Stream Whisper in pause-aligned chunks

**Decision.** While the user talks, audio is sent to Whisper in chunks that end in the middle of a natural pause (at least 0.3 s of near-silence, chunks 6–20 s long). On release only the remainder is transcribed. Each chunk gets the end of the previous chunk's text as context.

**Why.** Transcribing everything on release made the wait grow with length (2.8 s for a 70 s dictation). Streaming keeps it around 0.6 s at any length.

**What was rejected.** Fixed 5-second chunks. Cutting at arbitrary points split words, and Whisper garbled or invented words at the seams: 7.1% of words wrong on a 70 s test versus 3.8% all at once. Pause-aligned cuts gave the same words as all at once (both 3.8%, and those were formatting such as "back end" and "8%").

**Trade-off.** Seams sometimes turn a comma into a full stop (". And we have…"), because Whisper ends each chunk as a sentence. The cleanup step usually repairs this. Dictations under about 6 seconds aren't chunked and behave exactly as before.

**Checked by** `UtterChecks` (where cuts land) and `Utter --probe-whisper-stream` (end to end, in real time).
