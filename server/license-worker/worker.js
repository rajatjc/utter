// Utter license delivery: a Cloudflare Worker that receives Lemon Squeezy's
// "order_created" webhook, signs a license key for the buyer, and emails it
// through Resend. Keys are the same format scripts/license.swift makes and the
// app checks offline (UtterCore/Licensing.swift):
//   UTTER-<base64url JSON payload>.<base64url Ed25519 signature of the payload>
//
// Secrets (set with `wrangler secret put NAME`, never in this file):
//   LEMON_SQUEEZY_SIGNING_SECRET  the webhook's signing secret
//   UTTER_SIGNING_KEY             base64 private key from the signing-key file
//   RESEND_API_KEY                for sending the email
// Plain variables (wrangler.toml): MAIL_FROM, PRODUCT_NAME.

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method !== "POST" || url.pathname !== "/webhooks/lemonsqueezy") {
      return new Response("Not found", { status: 404 });
    }
    const body = await request.text();
    if (!(await validWebhook(body, request.headers.get("X-Signature"), env.LEMON_SQUEEZY_SIGNING_SECRET))) {
      return new Response("Bad signature", { status: 401 });
    }

    const event = JSON.parse(body);
    if (event?.meta?.event_name !== "order_created") return new Response("Ignored");
    const order = event.data?.attributes ?? {};
    if (order.status !== "paid") return new Response("Not paid");

    const name = order.user_name || order.user_email;
    const email = order.user_email;
    if (!email) return new Response("No email on order", { status: 422 });

    const key = await issueKey({ name, email, edition: "pro" }, env.UTTER_SIGNING_KEY);
    await sendEmail(env, email, name, key);
    // Returning an error makes Lemon Squeezy retry, so only succeed once the email is sent.
    return new Response("Sent");
  },
};

/** HMAC-SHA256 of the raw body, hex, compared in constant time. */
async function validWebhook(body, signature, secret) {
  if (!signature || !secret) return false;
  const key = await crypto.subtle.importKey("raw", utf8(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const expected = hex(new Uint8Array(await crypto.subtle.sign("HMAC", key, utf8(body))));
  if (expected.length !== signature.length) return false;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ signature.charCodeAt(i);
  return diff === 0;
}

/** Signs {edition, email, issued, name} with the Ed25519 private key (32-byte seed, base64). */
export async function issueKey({ name, email, edition }, privateKeyBase64) {
  const seed = fromBase64(privateKeyBase64.trim());
  if (seed.length !== 32) throw new Error("UTTER_SIGNING_KEY must be the 32-byte base64 key from the signing-key file");
  const publicKey = await publicKeyFromSeed(seed);
  const signingKey = await crypto.subtle.importKey(
    "jwk",
    { kty: "OKP", crv: "Ed25519", d: base64url(seed), x: base64url(publicKey) },
    { name: "Ed25519" },
    false,
    ["sign"],
  );
  // Keys in sorted order to match the Swift encoder (not required for verification).
  const payload = utf8(JSON.stringify({ edition, email, issued: Math.round(Date.now() / 1000), name }));
  const signature = new Uint8Array(await crypto.subtle.sign({ name: "Ed25519" }, signingKey, payload));
  return `UTTER-${base64url(payload)}.${base64url(signature)}`;
}

/** WebCrypto needs the public half in the JWK; derive it from the seed via PKCS#8. */
async function publicKeyFromSeed(seed) {
  const pkcs8 = new Uint8Array([
    0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20, ...seed,
  ]);
  const key = await crypto.subtle.importKey("pkcs8", pkcs8, { name: "Ed25519" }, true, ["sign"]);
  const jwk = await crypto.subtle.exportKey("jwk", key);
  return fromBase64(jwk.x.replace(/-/g, "+").replace(/_/g, "/"));
}

async function sendEmail(env, to, name, key) {
  const product = env.PRODUCT_NAME || "Utter";
  const text = [
    `Hi ${name},`,
    "",
    `Thanks for buying ${product}! Here is your license key:`,
    "",
    key,
    "",
    `To activate it, click the ${product} icon in the menu bar, open Settings → License, paste the key and click Activate.`,
    "The key is checked on your Mac; nothing is sent anywhere.",
  ].join("\n");
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${env.RESEND_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: env.MAIL_FROM, to: [to], subject: `Your ${product} license key`, text }),
  });
  if (!response.ok) throw new Error(`Email failed: ${response.status} ${await response.text()}`);
}

const utf8 = (s) => new TextEncoder().encode(s);
const hex = (bytes) => [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
const fromBase64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
const base64url = (bytes) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
