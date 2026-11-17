# Authentication contract

Every way into an Allure account is strong. An account signs in either with its
password *and* a second factor verified by Allure, or through an identity
provider (Apple, Google, or a generic OpenID Connect provider) whose own
authentication is trusted. Every account holding a password must enrol a second
factor after a grace period; the instance operator has none. `DESIGN.md`
governs the visuals and copy; where the two conflict on a data or security
contract, this document wins.

It extends the existing Rails 8 authentication (`Authentication` concern,
`Session` rows, signed `session_id` cookie, `has_secure_password`,
`SessionsController` rate limit, suspension, invitations) and adds no
authentication framework: no Devise, no Rodauth, no authorization gem.

## 1. Product decisions

1. **Two sign-in paths, each strong on its own.**

   | Path | Proof |
   |---|---|
   | Email + password | password **and** an Allure second factor: authenticator code (TOTP), passkey, or one-time recovery code |
   | Identity provider | the provider's own sign-in; Allure asks no further factor |

2. **Paths are judged independently.** An account may hold a password and any
   number of linked provider identities. Signing in through a linked provider
   skips Allure's second factor; signing in with the password always requires
   it. A provider sign-in never weakens the password path, and the reverse.
3. **Password-less accounts exist.** An account created through a provider has
   no password and therefore no second-factor obligation. Adding a password
   later starts that obligation and its grace period.
4. **Provider strength is a trust decision, not a verification.** The tokens do
   not carry a dependable MFA claim, so Allure trusts the provider by policy. A
   generic OIDC provider may be configured to require a specific `acr` (§6.4)
   when the operator wants a verifiable guarantee.
5. **Second factor for every password account, with a grace period**
   (`AUTH_2FA_GRACE_DAYS`, default 14). After it, the password path leads only
   to enrolment.
6. **The operator has no grace period** and must hold an Allure second factor
   whatever path they sign in with, because `/admin` re-confirms it (§5.4).
7. **Passkeys ship with TOTP.** They are created discoverable so a later
   passwordless passkey sign-in needs no re-enrolment, but passwordless
   sign-in is out of scope here.
8. **No "disable 2FA".** Factors can be added, renamed, replaced, and removed,
   but the last factor of a password account cannot be removed.
9. **Allure is a relying party only.** It never becomes an identity provider
   and issues no tokens to third parties.

## 2. Components

| Purpose | Component |
|---|---|
| TOTP | `rotp` |
| Enrolment QR code | `rqrcode`, rendered as inline SVG |
| Passkeys / security keys | `webauthn` (webauthn-ruby); browser side is a Stimulus controller over `navigator.credentials`, no extra npm package |
| Provider handshake | `omniauth`, `omniauth-rails_csrf_protection` |
| Generic OIDC and Google | `omniauth_openid_connect` (discovery, PKCE, nonce, JWKS) |
| Sign in with Apple | `omniauth-apple` (form-post response, JWT client secret) |
| Dev/CI provider | Dex in Compose behind the `oidc` profile (§10) |

No Redis and no new production service. Every provider is enabled only when
its environment variables are present; with none set the sign-in page is
unchanged apart from the second-factor step.

## 3. Configuration

`Allure::Auth::Config` is the single source, read at call time, following the
`Allure::Federation::Config` pattern. The relying-party identity (WebAuthn
RP ID and origin, OAuth callback URLs) derives from
`Allure::Federation::Config` — scheme, host and port — and is never hardcoded.

| Variable | Meaning |
|---|---|
| `AUTH_2FA_GRACE_DAYS` | grace period for password accounts (default `14`, `0` allowed) |
| `AUTH_SESSION_IDLE_DAYS` | idle session lifetime (default `30`) |
| `AUTH_SESSION_MAX_DAYS` | absolute session lifetime (default `90`) |
| `AUTH_GOOGLE_CLIENT_ID`, `AUTH_GOOGLE_CLIENT_SECRET` | enable Google |
| `AUTH_APPLE_SERVICES_ID`, `AUTH_APPLE_TEAM_ID`, `AUTH_APPLE_KEY_ID`, `AUTH_APPLE_PRIVATE_KEY` | enable Sign in with Apple |
| `AUTH_OIDC_ISSUER`, `AUTH_OIDC_CLIENT_ID`, `AUTH_OIDC_CLIENT_SECRET`, `AUTH_OIDC_LABEL` | enable one generic OIDC provider |
| `AUTH_OIDC_REQUIRED_ACR` | optional; a generic sign-in whose `acr` differs is refused |
| `AUTH_OIDC_REQUIRED_AMR` | optional; a generic sign-in whose `amr` lacks this method (RFC 8176, e.g. `mfa`) is refused |
| `IOS_APP_IDS` | `TEAMID.bundle` list served in `apple-app-site-association` (§9) |

Provider sign-up follows the existing registration gate exactly:
`Allure::Registration.open?` and single-use invitations. No separate
provider-registration switch exists. All keys are documented in
`.env.example` and the production env example; secrets never render.

## 4. Data model

All changes are migrations with matching model validations; schemas are
dumped by Rails.

### 4.1 `users`

| Column | Notes |
|---|---|
| `password_digest` | becomes nullable; a password-less account has at least one identity (service invariant, §6.5) |
| `otp_secret` | `encrypts`, nullable; set only after a confirmed enrolment |
| `otp_last_used_step` | bigint, nullable; replay guard |
| `otp_enrolled_at` | nullable |
| `second_factor_required_since` | nullable; set when the account first holds a password (creation, password added); backfilled to the migration time for existing password accounts; cleared when a password is removed (removing a password is not offered) |

`has_secure_password validations: false` with explicit validations: length
(`MINIMUM_PASSWORD_LENGTH`) and confirmation whenever a password is being set.

`User#second_factor_enrolled?` is true when `otp_enrolled_at` is present or
the account has at least one passkey.

### 4.2 `webauthn_credentials`

`user_id`, `external_id` (base64url, unique), `public_key`, `sign_count`,
`nickname` (≤ 60), `transports` (array), `backed_up` (boolean),
`last_used_at`, timestamps. Users have `webauthn_id` (random, unique, set on
first registration) as the WebAuthn user handle — never the bigint id or the
username.

### 4.3 `recovery_codes`

`user_id`, `code_digest`, `used_at`. Ten codes per generation, format
`xxxxx-xxxxx` from a lowercase base32 alphabet without ambiguous characters
(50 random bits each). The digest is an HMAC-SHA256 keyed from the
application's key generator, unique and looked up directly: with that much
entropy a keyed hash keeps the column useless without the secret, and a slow
hash would cost ten bcrypt comparisons per attempt. Shown once; regenerating
deletes the previous set. Generated automatically at the first enrolment.

### 4.4 `identities`

`user_id`, `provider` (`google`, `apple`, `oidc`), `issuer`, `subject`,
`email` (as last reported), `email_verified`, `linked_at`, `last_used_at`,
timestamps. Unique on `(issuer, subject)`; unique on `(user_id, provider)` so
an account links at most one identity per provider. The subject is the only
key: **an identity is never matched or linked by email.**

### 4.5 `sessions`

| Column | Notes |
|---|---|
| `auth_method` | `password` or `provider:<name>` |
| `second_factor_method` | `totp`, `webauthn`, `recovery_code`, or null |
| `second_factor_at` | last Allure second-factor verification (sign-in, step-up) |
| `reauthenticated_at` | last re-authentication (§5.5) |
| `enrolment_only` | boolean; the session may only reach enrolment and sign-out (§5.3) |
| `last_seen_at` | refreshed at most every 5 minutes |

### 4.6 `session_handoffs` (iOS, §9)

`token_digest` (SHA-256 of the token, unique), `code_challenge` (S256, 43
characters), `payload` (encrypted: the verified provider answer, its intent
and invitation token), `expires_at` (60 s). A handoff carries the provider's
answer, not a decided session: the app's web view resolves it (§9). It is
redeemed by its deletion, so any attempt — with the right verifier or not —
spends it; `Users::PruneExpiredSessionsJob` sweeps uncollected rows.

## 5. Password path and second factor

### 5.1 Sign-in flow

1. `POST /session` verifies the email and password (unchanged rate limit and
   suspension handling).
2. **No `Session` row is created yet.** The encrypted Rails session receives
   `pending_sign_in`: user id, an HMAC fingerprint of the id and
   `password_digest` (a password change invalidates it), `expires_at`
   (5 minutes), and an attempt count.
3. Then, by `Auth::SecondFactorPolicy`:
   - enrolled → redirect to `GET /session/challenge/new`;
   - not enrolled, inside the grace period → full session, banner (§5.3);
   - not enrolled, grace expired or operator → session with
     `enrolment_only: true`, redirect to `/settings/security`.
4. `POST /session/challenge` verifies one of: TOTP code, WebAuthn
   assertion, recovery code. Success clears the pending state, calls
   `start_new_session_for` with `second_factor_method` and
   `second_factor_at`, and returns to `after_authentication_url`.
5. Five failed attempts clear the pending state; the endpoint is also
   rate-limited per IP (10 per 3 minutes). Errors never say which part failed.

The second-factor page offers the passkey first when the account has one and
the browser can use it, then one code field that takes either an
authenticator code (six digits) or a recovery code; the format decides which
is checked. Registration also counts as the sign-in of a password account
(grace, or enrolment-only for the operator).

### 5.2 Factors

- **TOTP**: RFC 6238, SHA-1, 6 digits, 30 s, ±1 step drift. A step at or below
  `otp_last_used_step` is refused. Enrolment shows the QR code and the secret
  in text, and confirms only after a valid code; the secret is persisted on
  confirmation only. Replacing the authenticator re-runs the same flow.
- **Passkeys**: RP ID is the instance host from `Allure::Federation::Config`,
  origin its base URL. Registration requests a discoverable credential
  (`residentKey: preferred`) and `userVerification: preferred`. Assertions
  check origin, RP ID, challenge (stored in the Rails session, single use), and
  sign count (a decrease is logged and refused unless the count is zero,
  which synced passkeys report). Several passkeys per account, each nicknamed.
  Passkeys need a secure context: the browser side (a Stimulus controller over
  `PublicKeyCredential.parse*OptionsFromJSON` and `toJSON()`) hides the passkey
  controls where the browser cannot use them, which includes every plain-HTTP
  development host except `localhost`.
- **Recovery codes**: looked up by digest among the unused codes and marked
  used atomically. Using one sends an email (§7) and the security page shows
  how many remain.
- The first enrolled factor generates the recovery codes, lifts the enrolling
  session out of `enrolment_only`, and closes the account's other
  enrolment-only sessions, which only ever proved the password.

### 5.3 Enforcement and grace

`Auth::SecondFactorPolicy.for(user)` answers `:satisfied`, `:grace`
(with the deadline), or `:required`.

- The deadline is `second_factor_required_since + AUTH_2FA_GRACE_DAYS`; for
  the operator (`INSTANCE_OPERATOR_USERNAME`) it is
  `second_factor_required_since`, so the operator is `:required` immediately,
  including on a provider sign-in.
- Password-less accounts are `:satisfied` unless they are the operator.
- During `:grace` every page shows a dismissible-for-the-day banner with the
  remaining days and a link to enrolment (a same-day cookie hides it).
- The `Authentication` concern gains `enforce_second_factor_enrolment`: an
  `enrolment_only` session reaches only `/settings/security`, the enrolment
  controllers, re-authentication, sign-out, and the public pages; everything
  else redirects to the security page (a Turbo Frame request answers 204, and
  the notification bell is not rendered). Completing enrolment sets
  `second_factor_at` and clears `enrolment_only` on the current session.
- An existing full session whose user becomes `:required` (grace expired while
  signed in) is switched to `enrolment_only` on its next request.
- An `enrolment_only` session whose account gained a factor in another session
  (or from the console) is signed out on its next request: it only ever
  proved the password, so the next sign-in asks for the factor.
- **Demo exception** ([DEMO.md](DEMO.md)): when `DEMO_INSTANCE` is set the policy
  answers `:satisfied` for everyone, the operator included — nothing is owed,
  the banner never renders, and `counts` reports no `grace` or `required`. An
  account that *is* enrolled still answers its factor at sign-in; only the
  obligation is lifted. The exception is carried by the demo mode itself, not
  by a standalone switch: an ordinary instance cannot weaken its
  authentication this way.

### 5.4 Operator step-up

`Admin::BaseController` keeps its 404 for non-operators, then requires
`Current.session.second_factor_at` within 15 minutes. Otherwise it redirects
to the re-authentication page (§5.5), which for an enrolled account asks for
the password and a factor, and returns to the admin page. On a demo instance
([DEMO.md](DEMO.md)) the operator holds no factor at all, so a recent password
proof is accepted instead. This applies whatever path the operator used to
sign in.

### 5.5 Re-authentication

Sensitive actions require `reauthenticated_at` within 10 minutes:
email change, password addition, factor addition or removal,
recovery-code regeneration, identity linking or unlinking, account deletion,
and closing sessions (one other session or all of them), so a stolen cookie
cannot sign its owner out of their other devices. The password change keeps
its inline current-password field, which counts as re-authentication.

A gated GET returns to itself after confirmation; any other request returns
to the same-host page it was sent from (`Referer`), where the person repeats
the action — nothing is replayed. Signing in counts as re-authentication.
Re-authentication is the strongest available path for the account: the
password alone before enrolment, the password plus a factor (code, passkey,
or recovery code) once enrolled, or for a password-less account its enrolled
factor (code, passkey or recovery code) and otherwise a fresh provider sign-in
(`intent=reauthenticate`, `prompt=login`), which comes back to the page that
asked. A passkey alone is not accepted for re-authentication. A factor proved
here also refreshes `second_factor_at`. A successful second factor at sign-in
also counts as re-authentication.

### 5.6 Password reset

The reset token flow still destroys every session. The next sign-in goes
through §5.1, so **a reset never bypasses the second factor**.
The reset email is not sent to a password-less account, and the response does
not differ (no account enumeration). A password-less account adds a password
only from `/settings/security` after re-authentication, or through the
operator's setup link (§6.5).

### 5.7 Lost factors

Recovery codes are the self-service path. Otherwise the operator runs
`bin/rails users:reset_second_factor USERNAME=…` or uses the accounts panel in
`/admin`: both remove TOTP, passkeys and recovery codes, destroy the account's
sessions, set `second_factor_required_since` to now with **no grace**, email
the user, and write an `AdminEvent`. The operator cannot reset their own
factors from the console.

### 5.8 Logs

No authentication proof reaches a log. `filter_parameter_logging.rb` masks
passwords, tokens and secrets, and also every factor and handshake value:
`code` (authenticator, recovery and provider MFA codes, OAuth authorization
codes), `assertion` and `credential` (passkeys), `verifier` (the iOS
handoff's PKCE secret), and Sign in with Apple's `user` JSON string (name and
email), matched by value so that `user[...]` forms stay readable. An unspent
recovery code — a wrong password beside a valid code, a challenge that
expired — would otherwise stay valid in the log indefinitely.
`filter_redirect` masks the `allure://auth/handoff` location, whose token
Rails would log verbatim. `spec/config/filter_parameter_logging_spec.rb`
pins the list.

## 6. Identity providers

### 6.1 Endpoints

- `POST /auth/:provider` — request phase, POST only with CSRF protection
  (`omniauth-rails_csrf_protection`). The intent (`sign_in`, `link`,
  `reauthenticate`), an invitation token and `prompt` travel in the query
  string, which OmniAuth hands back to the callback as `omniauth.params`.
- `GET /auth/:provider/callback` — response phase (Google, generic OIDC).
- `POST /auth/apple/form_post` and `GET|POST /auth/apple/return` — Apple
  (below).
- `GET /auth/failure` — translated failure, back to sign-in.

OmniAuth registers the enabled providers at boot from
`Allure::Auth::Providers`; changing a provider's variables needs a restart.
Its `full_host` is `FEDERATION_BASE_URL`, so every callback URL derives from
the federation identity.

**Apple form-post and cookies.** Apple's callback is a cross-site POST, so the
`SameSite=Lax` Rails session cookie is not sent and OmniAuth's `state` and
`nonce` would be lost. Apple's `redirect_uri` is therefore
`/auth/apple/form_post` (`AppleFormPostsController`), a session-less page that
copies Apple's four fields (`code`, `state`, `id_token`, `user`) into a form
re-posted at once to `/auth/apple/return`, OmniAuth's Apple `callback_path`.
That second POST is same-site, so the session cookie and its `state` arrive;
OmniAuth verifies `state`, and the application session cookie keeps
`SameSite=Lax`. No middleware and no second cookie are added.

### 6.2 Callback resolution

`Auth::ProviderSignIn` receives the verified OmniAuth hash:

1. **Known identity** `(issuer, subject)` → suspended account refused as on the
   password path; otherwise a full session with `auth_method:
   provider:<name>`, no second factor (unless the user is the operator, who
   then gets `enrolment_only` or a `second_factor` prompt per §5.3). The
   session's proof of identity (`reauthenticated_at`) is the provider's
   `auth_time` when the token carries one (some providers report it; Google
   does not), never later than now, else the sign-in itself: a single sign-on
   session days old owes a fresh proof before a sensitive action (§5.5) like
   any password session.
2. **Unknown identity, signed in, linking intent** (`intent=link`, from the
   settings page; a session not re-authenticated within the window is sent to
   §5.5 first) → identity linked to the current account, email sent. An
   identity already linked elsewhere is refused. The `reauthenticate` intent
   accepts only an identity of the current account, asks the provider to
   authenticate the person again (`prompt=login`, `max_age=0`), and refreshes
   `reauthenticated_at` to the reported `auth_time`; an answer whose
   `auth_time` is older than the re-authentication window is refused
   (« n'a pas vérifié votre identité à nouveau »). A provider reporting no
   `auth_time` is trusted on the request.
3. **Unknown identity, not signed in**:
   - registration closed and no invitation → refused with the
     closed-registration copy, whether or not the address belongs to an
     account, so a provider identity never tells whether an address is
     registered; the copy also tells a member to sign in with their password
     and link the provider;
   - an account already uses the same verified email → refused with « Un
     compte utilise déjà cette adresse. Connectez-vous avec votre mot de passe
     puis associez ce fournisseur dans les réglages. » No automatic link.
   - registration open or an invitation token is pending → onboarding (§6.3).

The provider must return an email with `email_verified` true (Apple's private
relay addresses are accepted); otherwise the sign-in is refused.

### 6.3 Onboarding

`GET/POST /auth/onboarding` holds the verified identity in the encrypted Rails
session for 15 minutes and asks only for what becomes permanent:

- **username**, pre-filled from `preferred_username` or the email local part,
  sanitized to `USERNAME_FORMAT`, checked against `RESERVED_USERNAMES`, the
  configured instance name, the operator name, and the live availability
  endpoint — it is the permanent federation identity;
- display name (Apple's name arrives only on the very first authorization and
  is used as the default).

The locale is the page's. The account is created without a password, with
the provider's email — or the invitation's address when the sign-up came from
an invitation, whose token is then consumed — the actor provisioned as for any
registration, and a full session started (`Authentication#begin_sign_in`,
which also applies the operator rule of §6.2).

### 6.4 Provider specifics

- **Google**: OIDC with discovery at `https://accounts.google.com`, scopes
  `openid email profile`.
- **Apple**: `omniauth-apple`, scopes `name email`, `response_mode=form_post`,
  client secret JWT signed with the configured key. Requires a paid Apple
  developer account, a Services ID with the callback URL, and domain
  verification; HTTPS only.
- **Generic OIDC**: discovery from `AUTH_OIDC_ISSUER`, authorization code with
  PKCE, `state` and `nonce`. When `AUTH_OIDC_REQUIRED_ACR` is set, the request
  carries `acr_values` and a token whose `acr` differs is refused; when
  `AUTH_OIDC_REQUIRED_AMR` is set, a token whose `amr` lacks that method is
  refused (some providers vary `acr`, others list `mfa` in `amr`). The claims
  are read from the strategy's `extra.raw_info`, into which
  `omniauth_openid_connect` merges the ID token's claims after verifying its
  signature, issuer, audience, nonce and expiry; Allure never decodes an ID
  token itself. Only asymmetric signatures are accepted (§6.7); Google's are
  pinned to RS256.
- Outbound discovery and token requests are made by the gems; they are not
  subject to the federation SSRF guard but only ever reach configured issuers.

### 6.5 Linking and unlinking

`/settings/security` lists linked identities and offers « Associer » for each
enabled provider not yet linked. Unlinking requires re-authentication and is
refused when it would leave the account with neither a password nor an
identity. A user whose provider is disabled by the operator keeps the row; if
it was their only method, the operator re-enables the provider or runs
`bin/rails users:send_password_setup USERNAME=…`, which emails the
password-reset link to the password-less account (audited as
`password_setup_sent`; the new password starts §5.3 with no grace).

### 6.6 Sign-out

Sign-out is local only: the `Session` row and cookie go. RP-initiated logout
and back-channel logout are out of scope.

### 6.7 Strategy hardening

`Allure::Auth::ProviderStrategyHardening` is prepended to the
`openid_connect` strategy at boot (Google and the generic provider):

- A callback carrying a `nonce`, `code_verifier` or `redirect_uri` parameter
  is refused (`forged_callback`) before any token request. The strategy would
  otherwise verify the ID token's nonce against the parameter instead of the
  session, exchange the code with the parameter's verifier instead of the
  session's, and append the parameter to the registered callback: an
  attacker who learned a victim's pending `state` could then sign the victim
  into the attacker's account with the attacker's own code and PKCE pair.
  The session alone binds a callback to the browser that started the round
  trip, and the registered callback URL is the only `redirect_uri` ever sent.
- An ID token whose header names an HMAC algorithm (`HS256`, `HS384`,
  `HS512`) or `none` is refused whatever the provider's metadata offers: the
  strategy would verify it with the client secret, which must never become a
  key that signs identities. Google's tokens are pinned to `RS256`.
- The strategy's RP-initiated logout path (`/auth/:provider/logout`), which
  would redirect anyone to the provider's end-session endpoint, is not served.

The Apple strategy keeps its session-only `state` and `nonce` and is not
covered. RSpec drives the real strategy against a Rack environment with test
mode off (`spec/lib/allure/auth/provider_strategy_hardening_spec.rb`).

### 6.8 Session boundary

`start_new_session_for` rotates the CSRF token: a token read from a page
before the sign-in (a planted session, a pre-login page) is worth nothing
after it. The Rails session itself is kept, so `return_to_after_authenticating`
survives.

## 7. Notifications

Emails (Action Mailer, both locales, `DESIGN.md` voice) are sent for:
second factor enrolled or removed, recovery code used, recovery codes
regenerated, passkey added, identity linked or unlinked, password added or
changed, factors reset by the operator. They name the device's user agent and
time, never the IP address in full. No in-app notification kind is added.

## 8. Sessions

- The encrypted Rails state cookie (`_allure_session`, distinct from the
  authentication `session_id`) persists across browser and iOS companion
  restarts, with `expire_after` set at boot to `AUTH_SESSION_MAX_DAYS`.
  This keeps CSRF state when the sign-in cookie survives a cold launch;
  it does not extend the authenticated Session row's lifetime. The import
  form is excluded from Turbo's snapshot cache to avoid stale CSRF tokens.
- `start_new_session_for` keeps its cookie, but the cookie expires at the
  absolute lifetime (it is not `permanent`).
- `find_session_by_cookie` rejects and destroys a session idle longer than
  `AUTH_SESSION_IDLE_DAYS` or older than `AUTH_SESSION_MAX_DAYS`, and refreshes
  `last_seen_at` at most every 5 minutes.
- The existing session list on `/settings/security` shows the sign-in time,
  the last activity, and the lifetime rule; the sign-in method and the second
  factor used are listed with it.
- `Users::PruneExpiredSessionsJob` deletes expired rows daily (recurring, 4:30);
  Action Cable and the engagement metrics count live sessions only.
- Changing or adding a password destroys the other sessions; the current one
  survives.
- **Unfinished steps never pass to the next person.** The browser session
  holds them: the pending sign-in, the provider identity awaiting account
  creation, the authenticator secret being enrolled, recovery codes awaiting
  their one-time page, the WebAuthn challenges, the iOS handoff mark, and the
  re-authentication return path (`Authentication::AUTHENTICATION_FLOW_KEYS`).
  Every sign-in (`start_new_session_for`) and every end of a session —
  sign-out, closing every session, and the expiry, suspension and
  enrolment-only ends in `find_session_by_cookie` — clears them;
  `return_to_after_authenticating` stays, being the next person's own. The
  enrolment secret and the fresh recovery codes are also bound to the
  account that created them and are ignored by any other. « Annuler » on the
  second step (`POST /session/challenge/cancel`) and on account creation
  (`DELETE /auth/onboarding`) discard their state at once; no GET clears
  anything, since Turbo prefetches links.

## 9. iOS companion

The companion is a separate repository; this repository owns the server side.

- **Provider sign-in leaves the web view.** Google refuses embedded web views.
  Inside a companion that registers the `auth-session` bridge component, every
  provider button (sign-in, sign-up, linking, re-authentication) is a
  `bridge--auth-session` button carrying the absolute start URL
  `FEDERATION_BASE_URL/auth/ios/:provider?intent=…` (plus the invitation
  token or `prompt=login`); an older companion gets no provider button. The
  app checks that the URL is its instance's — scheme, host and port — and the
  start path, adds the PKCE challenge it generated (`code_challenge`,
  `code_challenge_method=S256`), and opens it in `ASWebAuthenticationSession`
  (callback scheme `allure`, shared with Safari's sign-ins).
- `GET /auth/ios/:provider` (`CompanionProviderStartsController`) validates
  the provider and the challenge, refuses a start from another site (`403`
  when `Sec-Fetch-Site` is present and neither `none` — the sign-in sheet's
  direct load — nor `same-origin`), stores the challenge as the system
  browser's round-trip marker, and renders a page that posts at once — with that
  browser's Rails token and a `same-origin` referrer policy, since
  `no-referrer` would send a null `Origin` the request phase refuses — to
  `/auth/:provider?client=ios&code_challenge=…&intent=…`.
- At the callback, `client=ios` decides nothing: the verified answer
  (`Auth::ProviderSignIn.portable` — the identity, the email and its
  verification, and the verified `acr`, never the ID token) is stored as a
  `SessionHandoff` (§4.6) and the browser is redirected to
  `allure://auth/handoff?token=…`. Only the attempt the start page opened in
  this browser is handed off: the marker is consumed and must equal the
  callback's challenge. A provider failure, a missing challenge or marker, or
  another attempt's challenge answer `allure://auth/handoff?status=failed`.
  PKCE stays the binding to the app; the marker is defence in depth.
- The app replies to the page with the token and its verifier (or
  `cancelled`, which changes nothing, or `failed`). The page posts them with
  its own Rails token to `POST /session/handoff`
  (`SessionHandoffsController`, rate-limited), which redeems the handoff —
  digest, expiry, single use, `BASE64URL(SHA256(verifier)) == challenge` —
  and resolves the answer through `Auth::ProviderSignIn` and the same
  responses as the browser callback (`ProviderSignInResponses`), in the web
  view's session: a known identity signs in (the operator then answers the
  second factor in the web view), a new one opens account creation, a link or
  re-authentication applies to the signed-in account, and a refusal returns
  with its flash. A token read from the redirect is useless without the
  verifier.
- **Sign in with Apple must be offered on iOS** whenever Google is (App Store
  guideline 4.8): Rails omits Google from the companion's buttons while Apple
  is not enabled (`Allure::Auth::Providers.for_companion`). Apple is the web
  flow in the system browser; native Sign in with Apple would need the
  server to accept an ID token for the app's own identifier, and is out of
  scope.
- **Passkeys in WKWebView** need Associated Domains (`webcredentials:<host>`)
  in the app and `/.well-known/apple-app-site-association` served by Rails
  from `IOS_APP_IDS` (404 when unset). The companion connects to any
  self-hosted instance, so the entitlement is opt-in per build: its
  `Allure.entitlements` names `webcredentials:$(ALLURE_PASSKEY_DOMAIN)`, which
  a build for one instance enables from its `Local.xcconfig`.
- TOTP and recovery codes work in the web view unchanged.
- The companion's bundled `path-configuration.json` marks the second-factor
  and account-creation pages as authentication pages, like sign-in, so
  leaving them replaces the native history; re-authentication and enrolment
  are pages of a signed-in session and keep it.

## 10. Development and tests

- **Dex** runs under the Compose `oidc` profile with a static user and the
  issuer `http://dex.test:5556/dex`, listening on the port it publishes (the
  federation-ring rule): one URL resolves from the host browser, the Rails
  container, and the Playwright browser. Host prerequisite:
  `127.0.0.1 dex.test`.
- Google and Apple need HTTPS callbacks; they are tested against the real
  providers only through a tunnel, never in CI.
- WebAuthn requires a secure context and an origin equal to
  `FEDERATION_BASE_URL`, so the plain-HTTP development and ring hosts never
  offer passkeys; RSpec covers them end to end with `WebAuthn::FakeClient`,
  and a browser check needs an HTTPS deployment.
- The development seeds give the demo accounts a fixed, public authenticator
  secret, so the seeded operator signs in with a second factor; the federation
  ring's integration sessions answer the second step with it.
- RSpec stays offline: every provider answers through
  `OmniAuth.config.test_mode` with mocked identities (`spec/support/omniauth.rb`,
  which also enables the three providers through their variables); the gems'
  discovery, JWKS and token code is exercised against Dex in the browser, not
  in RSpec. Passkeys use `WebAuthn::FakeClient`; TOTP uses `travel_to`.
- Coverage: pending state never creates a session; replay and drift; recovery
  single use; grace, expiry and operator rules; `enrolment_only` gate;
  step-up; re-authentication windows; reset not bypassing 2FA; no email
  linking; onboarding username rules; last-method guard; Apple form-post page;
  handoff single use, expiry and verifier; idle and absolute lifetimes; no
  account enumeration on reset. The companion's handoff is verified in the
  browser with Dex and a stand-in bridge adapter; the native sheet only on a
  simulator or device.

## 11. Metrics

Two gauges without identifiers: `allure_users_second_factor{state="satisfied|grace|required"}`
and `allure_users_sign_in_methods{method="password|provider"}`, mapped to the
`/admin` accounts panel in `Metrics::Catalog` ([METRICS.md](METRICS.md)).

## 12. Federation boundary

The federation boundary is untouched by this contract. ActivityPub HTTP
Signatures, inbox admission, signed object and media GETs, WebFinger, NodeInfo
and the `/metrics` bearer token are not user sign-in. The username chosen at
onboarding is a permanent actor identity exactly like a password
registration's.

## 13. Out of scope

- **Passwordless passkey sign-in**: passkeys are created discoverable so a
  later passwordless sign-in needs no re-enrolment, but the password path
  always requires a factor.
- **RP-initiated and back-channel logout**: sign-out is local only.
- **Native Sign in with Apple**: the web flow in the system browser is used.
- **Allure as an identity provider**: it is a relying party only.
- **The companion's native code**: a separate repository.
