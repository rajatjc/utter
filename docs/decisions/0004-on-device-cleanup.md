# 0004: On-device cleanup by default; Claude optional

**Decision.** Dictation cleanup uses Apple's on-device model (FoundationModels, macOS 26+) by default. Claude is an option, and is required only for Command mode.

**Why.** Free, private, offline, and fast enough (about a second). Users shouldn't need an API key or a subscription to dictate.

**Guard.** The small model sometimes answers a dictated question ("what's the capital of France" → "Paris."). `CleanupGuard` rejects outputs that don't mostly reuse the speaker's words and falls back to offline cleanup.

**Note.** Claude subscriptions (claude.ai logins) can't be used by third-party apps; Claude features need an API key, or later a hosted backend.
