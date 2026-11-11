# 0002: No live text while talking

**Decision.** While the user talks, the notch shows the orb and a waveform, not words. Live text is an opt-in setting.

**Why.** The live text came from Apple's recognizer, which silently restarts its transcription after a few seconds of silence, so earlier words vanished from the preview. Users found that more distracting than useful, and the typed text comes from Whisper anyway. Apple's recognizer no longer runs at all in the default mode.

**Related.** When Apple's recognizer is used, `SegmentStitcher` (UtterCore) detects its restarts and keeps the earlier text.
