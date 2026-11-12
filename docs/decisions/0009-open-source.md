# 0009: Open source under MIT

**Decision.** Utter is free and open source under the MIT License (2026-11-12). The license-key check, the 14-day trial, the License settings page, `scripts/license.swift` and `server/license-worker` were removed.

**Why.** Utter is shared as a side project for feedback and contributions rather than sold. A trial that locks the app contradicts "free", and MIT is the simplest license for others to use, change and build on.

**Trade-offs.** Anyone may sell or ship a closed copy. Going back to a paid model later is possible for new versions only: code already published under MIT stays MIT.

**Must not happen.** Third-party notices dropped from builds: FluidAudio (Apache-2.0) and the Parakeet model (CC-BY-4.0) keep their own terms, listed in `THIRD_PARTY_NOTICES.md` and copied into the app by `build.sh`.
