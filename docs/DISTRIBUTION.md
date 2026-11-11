# Selling Utter

Three things turn a build into something customers can buy: a Developer ID signature with notarization, a store, and license delivery. Everything on Utter's side is in place; each step below needs an account only you can create.

## 1. Sign and notarize

Without this, macOS tells buyers Utter "can't be opened" and they have to find **Open Anyway** in System Settings.

1. Join the [Apple Developer Program](https://developer.apple.com/programs/) (US$99 a year).
2. In Keychain Access or on developer.apple.com, create a **Developer ID Application** certificate and install it in your login keychain. Check that it's there:
   ```bash
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```
3. Create an app-specific password at [account.apple.com](https://account.apple.com) (Sign-In and Security → App-Specific Passwords), then save notary credentials once:
   ```bash
   xcrun notarytool store-credentials utter-notary \
       --apple-id you@example.com --team-id TEAMID --password xxxx-xxxx-xxxx-xxxx
   ```
4. Build, sign, notarize and staple:
   ```bash
   UTTER_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/make-dmg.sh
   ./scripts/notarize.sh
   ```

With a Developer ID identity, `build.sh` turns on the hardened runtime and applies `Resources/Utter.entitlements` (microphone and Apple events), as notarization requires. `notarize.sh` refuses a DMG that isn't signed that way, then submits it, waits, staples the ticket and checks it with Gatekeeper. Notarytool ships with the Command Line Tools; full Xcode isn't needed.

Customers who used a self-signed build need to turn Accessibility on again once after switching to the Developer ID build, because macOS ties that permission to the signature.

## 2. Open a store

[Lemon Squeezy](https://www.lemonsqueezy.com) is the suggested store: it's the merchant of record, so it collects and pays sales tax and VAT for you. Paddle works the same way.

1. Create a store and a product (for example "Utter, lifetime license").
2. Put the product's checkout link in `LicenseManager.purchaseURL` (`Sources/Utter/Features/LicenseManager.swift`). The **Buy Utter** button and the trial banner open it.

## 3. Deliver license keys

Keys are signed with an Ed25519 private key and checked offline by the app, so there's no license server to keep running. The private key is in `~/Library/Application Support/Utter-licensing/signing-key`. **Back it up somewhere safe** (a password manager): if it's lost, you can't issue keys that existing builds accept. Never commit it.

**By hand** (fine for the first sales): when an order arrives, make a key and email it.

```bash
swift scripts/license.swift issue --name "Buyer Name" --email buyer@example.com
```

**Automatically:** `server/license-worker` is a Cloudflare Worker that receives Lemon Squeezy's `order_created` webhook, checks its signature, signs a key and emails it through [Resend](https://resend.com).

1. In Resend, verify a sending domain and create an API key. Set `MAIL_FROM` in `server/license-worker/wrangler.toml` to an address on that domain.
2. Deploy the Worker and add its secrets:
   ```bash
   cd server/license-worker
   npx wrangler deploy
   npx wrangler secret put UTTER_SIGNING_KEY            # paste the contents of the signing-key file
   npx wrangler secret put RESEND_API_KEY
   npx wrangler secret put LEMON_SQUEEZY_SIGNING_SECRET # the secret you choose in step 3
   ```
3. In Lemon Squeezy → Settings → Webhooks, add `https://utter-license.<your-subdomain>.workers.dev/webhooks/lemonsqueezy`, choose a signing secret, and tick `order_created`.
4. Buy your own product in test mode and check that the email arrives and the key activates.

The Worker's signing and webhook handling were tested locally (keys verify in the app's format, forged webhooks are rejected, unpaid orders are skipped). It hasn't run against live Lemon Squeezy or Resend accounts yet.

## Trial

New installs get 14 days with everything on. The start date is kept in the Keychain, so deleting the app doesn't reset it. After the trial, dictation stops and Utter opens the License page; settings, history and the dictionary are kept.
