# 0008: Offline license keys

**Superseded by [0009](0009-open-source.md) (2026-11-12).** Utter is now open source; the key check, the trial and the key Worker were removed. Kept for history.

**Decision.** A license is a key signed with an Ed25519 private key; the app checks it against the public key built into it, without contacting a server. A 14-day trial starts on first launch.

**Why.** No server has to stay online for customers to keep using what they paid for, it works offline, and it works with any store. Keys can be made by hand (`scripts/license.swift`) or by the webhook Worker in `server/license-worker`.

**Trade-offs.** A key can be shared, and it can't be revoked without shipping a build that blocks it. That's acceptable for a one-time-purchase app at this stage. A cracked binary can skip the check entirely; no client-side scheme prevents that.

**Must not happen.** Losing the private key (no new keys would verify) or publishing it (anyone could make keys). It lives outside the repository in `~/Library/Application Support/Utter-licensing/`.
