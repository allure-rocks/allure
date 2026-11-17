# Push contract

Push notifications for the iOS companion. The in-app inbox stays the source of
truth, and push is one more delivery of the same rows to the companion app.
`DESIGN.md` governs the copy; where the two conflict on a data or security
contract, this document wins. The instance side is implemented here; the relay
and the companion are separate repositories.

## 1. Product decisions

1. **One relay, any instance.** The official app's APNs key belongs to the
   team owning its bundle identifier, so no self-hosted instance can reach
   APNs for it. A single relay operated by the app's publisher
   (`https://push.allure.rocks`, repository `allure-push-relay`) holds that key
   and translates Web Push into APNs. Every instance, allure.rocks included,
   is an ordinary client of the relay: no sign-up, no shared secret.
2. **End-to-end encrypted.** The instance encrypts each payload for the
   device (RFC 8291, `aes128gcm`) and signs the request (VAPID, RFC 8292). The
   relay sees an opaque blob; Apple sees the device token and delivery metadata,
   not the content. The app's Notification Service Extension decrypts and shows
   the text.
3. **Standard Web Push on the instance side.** Rails knows nothing about
   Apple; the same code can serve browser Web Push later.
4. **Opt-in, per device.** Permission is asked only when the account turns on
   « Recevoir sur cet iPhone » in `/settings/notifications`. Each device may
   hide the content (« Masquer le contenu »): the instance then sends the
   generic copy, still encrypted.
5. **A subscription lives with its session.** Signing out, an expired
   session, or a session closed from Security removes it (FK cascade). No
   push ever reaches a device for an account it is no longer signed into.
6. **The per-kind switches still decide.** A kind turned off is never
   created, so it is never pushed. Push adds no kind and no preference besides
   the device switch and the content switch.

## 2. Actors and secrets

| | Relay | Instance | iPhone |
|---|---|---|---|
| APNs key (`.p8`) of the official app | yes | no | no |
| Seal key (`RELAY_SEAL_KEYS`) | yes | no | no |
| Revocation key (`RELAY_REVOCATION_KEY`) | yes | no | no |
| VAPID key pair | no | its own | no |
| Device private key and `auth` secret | no | no | yes (shared keychain) |

A build signed by another team needs its own relay with its own APNs key: it
sets `ALLURE_PUSH_RELAY_URL` in the app and the instance lists that origin in
`PUSH_RELAY_ORIGINS`. The protocol does not change.

## 3. Relay protocol (v1)

Base URL `R`, e.g. `https://push.allure.rocks`. All bodies are JSON unless
stated; every error answers `{"error": "<code>"}`.

### 3.1 Register — `POST R/v1/register`

Request: `{"token": "<APNs device token, hex>", "environment": "sandbox" | "production", "vapid_key": "<instance VAPID public key>"}`.

Response `201`:

```json
{ "endpoint": "R/v1/push/<sealed>", "revocation_secret": "<base64url, 32 bytes>" }
```

- `<sealed>` is base64url (no padding) of
  `key_id (1 byte) ‖ nonce (12 bytes) ‖ AES-256-GCM(ciphertext ‖ tag)` over the
  compact JSON `{"t": token, "e": environment, "s": subscription_id, "k": key_digest}`, where
  `subscription_id` is 16 random bytes (base64url). Every registration gets a
  new identifier, so a device registered twice holds two distinct endpoints.
- `vapid_key` is the instance's VAPID public key (base64url, uncompressed
  P-256, 65 bytes), like a browser's `applicationServerKey` (RFC 8292 §4).
  `key_digest` is base64url of the first 16 bytes of its SHA-256: the endpoint
  only accepts pushes signed by that key, so a leaked endpoint is useless
  without the instance's private key, and a blocked key cannot be swapped for
  a fresh one.
  `RELAY_SEAL_KEYS` maps a key id to a 32-byte key; the newest seals, every
  listed key unseals (rotation).
- `revocation_secret = HMAC-SHA256(RELAY_REVOCATION_KEY, s)` where `s` is the
  subscription identifier's base64url string; the relay keeps nothing. The
  key-id byte is authenticated with the ciphertext; tokens are lowercased.
- `400` on a malformed token (not 64–200 hex characters), environment or
  `vapid_key` (`invalid_vapid_key`: not a P-256 point).

### 3.2 Push — `POST R/v1/push/<sealed>`

Web Push request (RFC 8030 / 8291 / 8292):

- `Content-Encoding: aes128gcm`, body at most **2 900 bytes** (`413` above:
  the base64 blob and the `aps` wrapper must fit APNs' 4 KB payload, which
  the relay also checks once built);
- `TTL: <seconds>` (required, 0–2 419 200), optional `Urgency`
  (`very-low`/`low` → APNs priority 5, otherwise 10);
- `Authorization: vapid t=<JWT>, k=<public key, base64url uncompressed P-256>`.
  The JWT is ES256, signed by `k`, `aud` equal to the relay origin, `exp` in
  the future and at most 24 h ahead, `sub` present (`mailto:` or `https:`).
  `k` must be the key the endpoint was registered with.

Answers:

| Code | Meaning |
|---|---|
| `201` | accepted by APNs |
| `400` | missing/invalid headers or TTL |
| `401` | VAPID missing or invalid |
| `403` | `{"error": "forbidden"}`: VAPID key or `sub` blocked by the relay operator; `{"error": "key_mismatch"}`: `k` is not the endpoint's key (the instance changed its VAPID key): delete the subscription |
| `404` | the endpoint does not unseal |
| `410` | revoked, or APNs answered `Unregistered`, `ExpiredToken`, `BadDeviceToken` or `DeviceTokenNotForTopic`: delete the subscription |
| `413` | body too large, or APNs' 413 |
| `429` | rate limit (per VAPID key, per subscription), with `Retry-After` |
| `503` | APNs unavailable (`Retry-After: 30`), throttling (`Retry-After: 60`), or any other APNs refusal — the relay operator's fault, so the instance retries and keeps the subscription |

Checks run in this order: body size, headers, VAPID, endpoint, endpoint key,
revocation, rate limits, APNs. An unauthenticated caller always gets `401` and
learns nothing about an endpoint. The `exp` bound tolerates 60 s of clock skew.

APNs request: topic `RELAY_APNS_TOPIC` (the bundle identifier), push type
`alert`, priority per `Urgency`, expiration `now + TTL`, environment from the
sealed endpoint, and the payload:

```json
{
  "aps": {
    "alert": { "title-loc-key": "ios.push.generic.title", "loc-key": "ios.push.generic.body" },
    "mutable-content": 1,
    "sound": "default"
  },
  "p": "<base64url of the encrypted body>"
}
```

The localized fallback is shown only when the extension cannot run or
decrypt.

### 3.3 Revoke — `POST R/v1/revoke`

Request: `{"endpoint": "<full endpoint URL>", "revocation_secret": "..."}`.
The relay unseals the endpoint (`404` otherwise), recomputes the secret and
compares in constant time (`403` otherwise), then records
`SHA-256(s)` for **90 days** — the absolute session lifetime,
after which the instance has dropped the subscription anyway. Answers `204`,
idempotent. This digest list is the relay's only state.

### 3.4 Operation

- No log line carries a token, an endpoint, a body or a VAPID JWT.
- `GET /healthz`; Prometheus counters at `/metrics` behind a bearer token
  (`relay_pushes_total{result}`, `relay_registrations_total`,
  `relay_revocations_total`).
- Rate limits: 600 pushes/minute per VAPID key, 60/minute per subscription,
  30 registrations/minute per client IP.
- `RELAY_BLOCKED_VAPID_KEYS` and `RELAY_BLOCKED_SUBJECTS` refuse an abusive
  instance with `403`.

## 4. Payload (v1)

The instance encrypts the compact JSON:

```json
{
  "v": 1,
  "origin": "https://allure.example",
  "id": "123",
  "url": "https://allure.example/notifications/123",
  "title": "Allure",
  "body": "Marie a commenté votre activité « Sortie du dimanche »",
  "badge": 3,
  "thread": "comment"
}
```

- `origin` is `Allure::Federation.config.base_url` (scheme, host, explicit
  port); `url` is `/notifications/:id` on it, which marks the row read and
  redirects (`NotificationsController#show`).
- `title` is `INSTANCE_NAME`, else the host; `body` is
  `NotificationsHelper#notification_text` in the recipient's locale, as plain
  text. With `hide_content`, `body` is `push.hidden_body`
  (« Vous avez une nouvelle notification ») and `thread` is `"allure"`.
- `badge` is the recipient's unread count; `thread` is the kind (reactions,
  comments and follow events each group).
- Never coordinates, workout content beyond the title the inbox already
  shows, or remote HTML. Encrypted plaintext stays under 2 KB.

## 5. Instance

- `push_subscriptions`: `user_id`, `session_id` (unique, FK cascade),
  `endpoint` (encrypted) with `endpoint_digest` (unique SHA-256),
  `p256dh`, `auth` (encrypted), `hide_content` (false), `last_success_at`,
  `failure_count`, timestamps. The endpoint's origin must be listed in
  `PUSH_RELAY_ORIGINS` (default `https://push.allure.rocks`): the instance
  never POSTs anywhere else (SSRF).
- `Allure::Push::Config` reads `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`
  (base64url, P-256), `VAPID_SUBJECT` and `PUSH_RELAY_ORIGINS`. Push is off —
  no job, no settings section — until the three VAPID values are set.
  `bin/rails push:vapid_keys` prints a fresh pair. Every endpoint is bound
  to the public key (§3.1): changing the pair cuts every device off until it
  registers again, which the settings page does on the next visit.
- `Settings::PushSubscriptionsController` (`/settings/push_subscription`,
  singular, the current session's): `create` (upsert from the bridge's
  answer; it replaces only the current account's earlier row for the same
  endpoint — an endpoint alone is never proof of ownership — and an invalid
  registration changes nothing), `update` (`hide_content`), `destroy`.
- `POST /push/unsubscribe` `{endpoint, auth}` needs no session and no CSRF
  token: knowing the device's `auth` secret is the proof. The app calls it
  natively when it leaves a server, since the web data is about to be wiped.
  Answers `204` whatever matched. Neither the endpoint nor `auth` ever
  reaches the log: both are proofs.
- `Notifications::Create` (and `ReactionDigest` when it alerts) enqueue
  `Notifications::PushJob` after commit for a row that is new or turned
  unread. A silent reaction type switch pushes nothing.
- `Notifications::PushJob` builds the payload per subscription, encrypts it,
  POSTs it with `TTL: 86400` through the SSRF-safe client, deletes the
  subscription on `404`/`410` and on `403 key_mismatch`, counts failures and
  deletes after 10 in a row, and records `last_success_at`. It never retries a
  `4xx`; `429`/`5xx` retry with back-off.
- `/metrics`: `allure_push_deliveries_total{result}` and
  `allure_push_subscriptions`.

## 6. Companion

- Bridge component `push`, shown only when the app announces it and push is
  configured:
  - `status` → `{"status": "unavailable" | "denied" | "off" | "on", "endpoint"?, "vapid_key"?}`
    (`unavailable`: build without push entitlements, or no relay URL;
    `vapid_key`: the key the endpoint is bound to);
  - `register` `{"vapid_key"}` (the instance's public key, which the page
    carries) → asks permission, registers with APNs and the relay, generates
    the key pair and answers
    `{"status": "registered", "endpoint", "p256dh", "auth"}` (base64url;
    `p256dh` uncompressed, 65 bytes; `auth` 16 bytes), or `denied`/`failed`;
    the **page** posts it to `/settings/push_subscription`. When `status` is
    `on` with another `vapid_key` than the instance's, the page registers
    again on its own: permission is already granted, so nothing is asked;
  - `unregister` → revokes at the relay, deletes the keys, answers `off`; the
    page deletes the subscription.
- Keys live in a keychain access group shared with the extension, keyed by
  the instance origin, with the endpoint, the revocation secret and the
  VAPID key the endpoint is bound to.
- The extension decrypts, checks `origin` against the stored instance
  (scheme, host and port) and `url` against that origin; on any failure it
  leaves the generic alert.
- A tap opens `url` in the visible tab when it belongs to the open instance;
  a cold launch waits for the first page, like shared files.
- Leaving a server: `POST /push/unsubscribe` to the old instance (best
  effort), revoke at the relay, delete the keys — before the web data is
  wiped.
- Push entitlements are opt-in (`Allure/Resources/AllurePush.entitlements`),
  like passkeys; a build without them answers `unavailable`.

## 7. Tests

Relay: register/seal/unseal round trip, key rotation, VAPID acceptance and
every refusal, the endpoint's VAPID key binding, revocation and its expiry,
rate limits, APNs answer mapping, no secret in logs. Instance: model
constraints and origin allowlist, controller scoping to the session,
unsubscribe proof, cascade on sign-out, job payload (locale, hidden content,
badge), encryption round trip, `410` and `key_mismatch` deletion, failure
counting, no job when unconfigured. Companion: RFC 8291 §5 test vector,
payload decoding, origin and URL checks, relay request building.

## 8. Deferred

- Withdrawing a delivered alert after `Notifications::Withdraw`.
- Badge sync on a read from another device.
- App Attest on registration.
- Browser Web Push.
