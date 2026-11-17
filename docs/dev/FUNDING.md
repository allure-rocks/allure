# Funding contract

The voluntary yearly contribution that helps an operator pay for their
instance, the supporter badge it grants, and the pluggable payment-provider
contract so another operator can write their own integration without touching
the core.

In the UI this is « Soutenir l'instance » / "Support this instance". It is a
contribution to the host, not a membership and not a feature gate: **nothing
in Allure is ever locked behind it**. The badge is purely honorific.

## 1. Scope

- Three tiers, named after the existing reaction types and drawn with the same
  pictograms: `coffee` (≈ 1 €), `beer` (≈ 5 €), `energy` (≈ 10 €). The actual
  amounts live at the payment provider, never in Allure, and are **per year**.
- An automated contribution is an **annual subscription with automatic
  renewal**, explicitly disclosed before checkout. Monthly billing, instalments,
  trials, prorated tier changes and mixed-product subscriptions are outside
  this contract. The hosted portal supports cancellation and payment-method
  management, not plan changes.
- Each verified paid annual invoice creates a separate contribution for its
  **billed period**, `[starts_at, expires_at)`, not `paid_at + 1 year`.
  Early or late payment does not move the billing anniversary. A payment
  received after its period ended is retained in history but grants no badge
  today. Manual grants remain one rolling year from the grant time, without
  automatic renewal.
- Cancellation stops future renewals; it never removes the badge for a paid
  period. A failed payment never extends that period. Subscription creation,
  an `active` provider status, a trial, or a checkout redirect alone grants
  nothing. No account access or application feature depends on billing state.
- Money never transits through Allure: the member is redirected to the
  provider's hosted checkout, and Allure only records a verified notification.
  No card data is stored or processed by Allure, and no amount is typed into
  Allure. The operator remains responsible for its payment-provider and
  compliance obligations.
- The whole feature sits behind the **`FUNDING_ENABLED`** master switch, off
  by default and read at call time (`Allure::Funding.enabled?`). While it is
  unset, nothing exists: no navigation entry, no settings group, 404 on
  `/funding`, the webhooks and `/admin/funding`, no metrics family — and the
  badge itself is not rendered, even for contributions already granted. The
  rows are retained, so turning the switch back on restores every badge;
  disabling the feature never deletes data. **This switch does not cancel
  subscriptions or stop external charges.** Before disabling the feature or
  a provider, the operator must stop renewals at that provider and tell affected
  supporters. Re-enabling reconciles missed invoices and subscription state
  before presenting renewal information as current.
- The iOS companion never sees the contribution surface: `/funding` and the
  settings card are not rendered when `hotwire_native_app?`. The badge itself
  is ordinary HTML and renders everywhere, companion included.
- The badge never federates: it is a local display decoration, never baked
  into avatar bytes (remote instances cache those), never a Note tag, never in
  a publication snapshot or sanitized representation.

## 2. Vocabulary

| term | meaning |
|---|---|
| contribution | one verified payment, one `FundingContribution` row |
| subscription | the durable link between a provider subscription and an Allure account; never a paid entitlement by itself |
| paid period | the annual service period of a verified paid invoice; determines badge validity |
| tier | `coffee` / `beer` / `energy` |
| supporter badge | the tier pictogram overlaid on the account's avatar |
| provider | one payment integration (`stripe`, `helloasso`, …) |
| reference | the signed token identifying the paying account across the redirect |

## 3. Data model

`funding_contributions`:

| column | meaning |
|---|---|
| `user_id` | nullable: an unmatched contribution waits for the operator |
| `provider` | `manual`, `stripe`, `helloasso`, … |
| `tier` | `coffee` / `beer` / `energy` (check constraint) |
| `external_id` | the original paid invoice id, or equivalent provider payment-period identity; unique per `(provider, external_id)`, never the webhook event id or subscription id; `manual` rows synthesize one |
| `funding_subscription_id` | nullable link to the subscription; nil for manual grants |
| `paid_at` | the provider's payment time (manual: the grant time) |
| `starts_at` | the verified billed period start; manual: `paid_at` |
| `expires_at` | the verified billed period end; manual: `paid_at + 1 year` |
| `status` | `active` → `revoked`; expiry is derived (`expires_at`), not a status |
| `amount_cents`, `currency` | optional, operator bookkeeping only, never displayed to other members |
| `metadata` | bounded diagnostic flags (for example `refund_reported`), never raw provider payloads, card data, names or addresses |

`funding_subscriptions` keeps provider state separate from paid periods:

- nullable `user_id` for an unmatched subscription;
- `provider`, `external_id` (provider subscription id, unique together), and
  `customer_id` for server-side portal-session creation; these are identifiers,
  not credentials, and never enter public pages, metrics labels or federation;
- the current configured `tier`, a bounded normalized provider status
  (`incomplete`, `active`, `past_due`, `paused`, `canceled`),
  `cancel_at_period_end`, optional `canceled_at`, and `synced_at`;
- no stored projection of badge entitlement: only paid contribution periods
  decide whether a badge is current. Subscription events cannot rewrite those
  periods or revoke them.

`funding_reversals` records verified reversal signals separately from the
immutable payments, so the operator can review them in `/admin/funding`:

- `provider` + `external_id` (the refund or dispute id, unique together) make
  redelivery idempotent; `funding_contribution_id` ties the reversal to the
  original paid invoice, resolved through the provider's own relationships;
- `kind` (`refund` / `dispute`) with a bounded per-kind `status` (refund:
  `succeeded` / `failed`; dispute: `open` / `won` / `lost` — a dispute whose
  charge was refunded is a loss);
- optional `amount_cents` / `currency` (partial vs full is derivable against
  the contribution's own amount) and the provider-verified `reported_at`;
- the contribution row is never rewritten: the badge-after-refund policy is
  unchanged and only the operator's manual revocation removes a badge.

An authenticated provider read-back refreshes subscription state rather than
blindly applying arrival-ordered webhook statuses. A stale notification must
not resurrect a canceled subscription. Multiple provider customers or
historical subscriptions may belong to one account; a customer email is never
an account-matching key. The UI directs an account with an existing live
subscription to manage it instead of offering another subscription checkout.

The model and recording seam preserve verified period ends instead of
overwriting them with `paid_at + 1 year`. Both application validation and
database checks enforce `expires_at > starts_at`.

`users`:

- `funding_badge_hidden` boolean, default false — the badge of an active
  contribution shows unless the account hides it. Hiding is one switch on
  `/settings/profile`; there is never a "non-supporter" signal.
- `funding_badge_color` — one of a fixed palette of theme-safe tokens
  (`primary`, `blue`, `teal`, `orange`, `purple`, `slate`, with validated
  contrast on both themes). Never a free hex value.

Derived state, computed on read (no stored projection):

- `User#active_funding_contributions` — `status: active` and
  `starts_at <= now < expires_at`; preloading must still check both boundaries;
- `User#funding_badge_tier` — the **highest** active tier
  (`energy > beer > coffee`);
- badge shown ⇔ `FUNDING_ENABLED` is set, a tier exists and
  `funding_badge_hidden` is false.

Account deletion purges the rows with the account (`Users::DeleteAccount`);
the data export includes the account's contributions in `account.json`
(provider, tier, dates — no provider payload). Suspension/deactivation hides
the badge like every other public-facing state (`User#deactivated?`).

Account deletion also stops future provider renewals, with an explicit
cancellation acknowledgement and durable, retryable confirmation before billing
identifiers are purged; it never leaves an anonymously orphaned subscription
charging after the account is gone. The lifecycle is coordinated with
`ACCOUNT.md`:

- `Funding::CancelSubscriptions` (the purge's `funding` phase) cancels every
  live subscription matched to the account at the provider — renewal stopped,
  paid periods retained — through the shared `cancel_one`, which raises
  `ProviderError` when no adapter can confirm, so the purge job retries. A
  provider 404 during cancellation is terminal only when the original account
  explains it; the adapter requires the persisted `customer_id` to still be
  retrievable in the answering account and the subscription to be absent from
  its full list — the customer id is the provenance anchor across credential
  rotation, so wrong-account or wrong-mode credentials fail closed instead of
  being trusted as a cancellation. Any unexplained 404 blocks the phase with
  the billing identifiers intact.
- A verified checkout reference resolves an account whose deletion is
  **scheduled** in a billing-only mode (`Funding::Reference.resolve
  for_billing: true`): a late initial notification then binds the subscription
  and claims its unmatched invoices as billing owner, without granting a badge
  or sending a notification (every benefit surface already hides deactivated
  accounts), so the purge's cancellation reaches it. A purely suspended or
  already deleted account never resolves, in either mode. Benefit eligibility
  and billing-lifecycle ownership stay separate: the operator's manual attach
  (`Funding::AttachSubscription`) still refuses deactivated accounts.
- Once the deletion has started — irreversible — a late verified notification
  cancels the renewal at the provider immediately. The binding commits first,
  so a provider failure makes the webhook answer 502 and retry rather than
  orphan a renewing subscription.
- While the window is still open the subscription is deliberately left live:
  a cancelled deletion restores a paid, manageable subscription, and a renewal
  falling due inside the seven-day window is cancelled by the purge.

## 4. The badge

Rendered by `avatar_tag` (and through it `actor_avatar_tag` for local actors;
a remote actor never carries one) as a Tabler avatar badge: a small circular
overlay on the avatar's corner carrying the tier's reaction pictogram, tinted
with `funding_badge_color`. Decorative by default like the avatar itself; when
`decorative: false`, the accessible name appends the §19 badge sentence.

It appears wherever the avatar does — profile, feed, comments, boards,
People — because it is the same helper. It is **never** composed into the
512×512 WebP or the generated SVG, so avatar caching, Gravatar and federation
are untouched.

`DESIGN.md` gains: §9 (avatar) the badge overlay and its palette, §19 the badge
copy — « Soutient cette instance » / "Supports this instance" — and the
no-negative-signal rule.

## 5. The provider contract

`Allure::Funding::Providers` is a registry in the mould of
`Allure::ImportSources` / `ImportConnections::Providers`. A provider is a
class registered under a slug, pure HTTP clients under
`lib/allure/funding/`, the Rails-facing seam under `app/services/funding/
providers/`. The contract, pinned by the `a funding provider` shared examples:

| member | contract |
|---|---|
| `.slug` | stable identifier, used in the webhook route and `funding_contributions.provider` |
| `.enabled?` | true only when the provider's env variables are complete and well formed; a disabled provider contributes nothing anywhere |
| `.checkout_url(tier:, reference:)` | the hosted-payment URL for the tier, carrying the signed reference however the provider allows; nil when the tier is not configured |
| `.verify!(request)` | authenticates the inbound notification **before reading the body as trusted** — an HMAC signature or a signed read-back against the provider's API — and returns a normalized `Allure::Funding::Event` or raises |
| `.portal_url(subscription:, return_url:)` | creates a short-lived hosted management session for a server-resolved, owner-scoped subscription; never accepts a customer id from the browser |
| `.portal_origin` | the HTTPS origin of the provider's hosted portal, allowed in the Content-Security-Policy `form-action` — Chrome checks that directive against the redirect of the portal form's POST too |
| `.reconcile` | enumerates paid annual invoices and refreshes subscription state from the authenticated API for recovery; required for automated annual subscriptions |

`Allure::Funding::Event` is a frozen value: `kind` (`payment` / `refund`),
`external_id`, `tier`, `reference` (nil when absent), `paid_at`,
`amount_cents`/`currency` when known, plus `subscription_id`, `period_start`
and `period_end` on verified payment/refund events. A separate normalized
subscription-state value carries the provider subscription id, customer id,
tier and lifecycle fields; it never grants a contribution. Unsupported events
return nil after verification. Before recording any invoice, the adapter must
resolve or create its matched or unmatched subscription row from verified
provider facts. `RecordContribution` refuses a missing subscription row and
derives the account only from that durable binding, never from an invoice's
checkout reference.

A notification may also carry a `reversal` (`Allure::Funding::Reversal`: kind,
external id, bounded status, optional amount/currency, provider-verified
`reported_at`, and the original invoice identity `payment_external_id`).
`Funding::RecordReversal` upserts it idempotently per `(provider, external_id)`
and never touches the original payment; reversals whose payment was never
recorded are ignored.

The **reference** is minted by `Rails.application.message_verifier(:funding)`
when the signed-in member clicks a tier: the account id, tier index and expiry
timestamp, valid 2 hours. To fit hosted payment links, the signed payload is
compact (no verifier metadata envelope); its explicit expiry is checked after
verification. The base64 message is transported URL-safe without padding and
joined to its hexadecimal signature with `_`, then reconstructed before
verification. It contains only alphanumerics, `-` and `_`, at most 200
characters. It survives the redirect, proves which account initiated the
checkout, and cannot be forged into pointing at an arbitrary account. The
short-lived reference binds the **initial checkout** to a durable subscription
row after authenticated provider read-back. For delayed delivery, its expiry is
checked at the provider-verified checkout creation time, not at renewal or
webhook receipt time. Subsequent invoices resolve only through the stored
`(provider, subscription_id)` binding; they do not reuse or extend the initial
reference's two-hour lifetime. No email-address matching is allowed. Missing or
invalid bindings leave invoices and subscriptions **unmatched**, rather than
discarding verified payments.

Invoice delivery may precede checkout delivery. Recovery must resolve the
provider-verified checkout binding and attach only still-unmatched rows in a
transaction, notifying once for a newly matched paid invoice. It must never
move an already matched invoice or subscription to another account. Explicit
operator attachment remains audited.

`Funding::RecordContribution` freezes the first verified payment's facts:
redelivery never changes the account, tier, paid date, period or revocation.
The database unique index arbitrates concurrent inserts. A refund marks
`metadata.refund_reported` without revoking or notifying. If it arrives before
the payment event, the verified refund's complete payment facts create the row
with that flag; a later payment cannot erase it. Refund adapters must therefore
resolve the original payment, not emit only a refund identifier. Invalid,
expired, deleted-account or deactivated-account references remain unmatched.
The `refund_reported` flag stays as a diagnostic; the operator-visible record
of a reversal is its `funding_reversals` row, which never revokes or rewrites
anything by itself. Notification is scheduled once after creation commits, only
for matched payment events. No raw provider payload is stored.

Adding a provider = one registered class satisfying the shared examples, its
env variables documented in `docs/site/configuration/environment.md` (the
guard spec enforces it), and nothing else: routes, controller, persistence,
admin and badge are provider-agnostic.

## 6. Flow

1. `/funding` (route `funding_path`, web only, signed-in like every surface —
   `ACCESS.md`; `funding` joins the application-route group of
   `User::RESERVED_USERNAMES`, whose guard spec enforces it) presents the
   three tiers with their pictograms, the operator's wording, and one button
   per configured tier. Buttons come from the enabled providers'
   `checkout_url`; with no provider but static links configured
   (`FUNDING_LINK_COFFEE|BEER|ENERGY`), the buttons are those links verbatim,
   with no reference and manual granting.
2. The member accepts the disclosed annual automatic renewal and pays on the
   provider's hosted page. The provider handles billing and renewal reminders.
3. The provider redirects the browser to `/funding/thanks` — a thank-you page
   stating the badge appears within minutes. **The redirect never grants
   anything.**
4. The provider notifies `POST /funding/webhooks/:provider`
   (`allow_unauthenticated_access`, CSRF exempt, 404 for an unknown or
   disabled provider). The controller calls `verify!`, then
   `Funding::RecordContribution`: idempotent upsert on
   `(provider, external_id)`, tier and account resolved from the event,
   period boundaries verified, and — when matched — the switchless
   `funding_recorded` notification to the account. The parsed body is never
   logged: before Rails' INFO parameter logging runs, the controller replaces
   the request parameters with a minimal envelope (event id and type,
   format-checked), and `filter_parameter_logging` masks the billing keys as
   defense in depth — billing names, addresses, invoice URLs and checkout
   references never reach the logs. A `refund` event only flags the row for
   the operator (`metadata`), never auto-revokes: the operator decides from
   `/admin`.
5. Each paid renewal invoice follows the same path, with its own invoice id
   and billed annual period. Failed invoices, payment retries and subscription
   lifecycle events never manufacture a new contribution.
6. A web-only, authenticated POST from `/funding` creates an owner-scoped hosted
   portal session; cancellation there stops renewal, not the already paid badge.
   The return URL is application-owned, and no portal URL is retained or logged.
7. `bin/rails funding:reconcile` replays each provider's `reconcile` window
   as the safety net for lost or reordered webhooks; idempotency makes it
   harmless. A recurring recovery job uses the same seam. Recover paid invoices
   even when the subscription has since been canceled; current provider status
   must not erase an earlier paid period.

The Stripe adapter is the reference implementation; its setup is documented
for operators.

## 7. Settings and admin

All of this section exists only while `FUNDING_ENABLED` is set.

- `/settings/profile` gains the « Badge de soutien » group: the hide switch
  and the color choice.
- `/funding` names the annual automatic renewal, shows each provider's verified
  current management state separately from the paid badge expiry, and offers
  « Gérer mon abonnement » / "Manage my subscription" to its hosted portal.
  A cancellation-scheduled state says the badge stays until the paid expiry.
  Failed-payment copy never implies loss of application access. Manual grants
  are explicitly non-renewing. All subscription and management controls are
  web-only and entirely absent from the companion.
- `/admin/funding`: every contribution (provider, tier, dates, status), its
  reversal badges (kind, outcome, amount), the **unmatched** rows with an
  account picker to attach them, and revocation. All mutations audited
  (`funding_granted`, `funding_attached`, `funding_revoked`) through
  `Admin::Audit`.
- `/admin/accounts/:id` gains a manual grant (tier + optional note → a
  `provider: manual` row) and the account's contribution list.
- `/metrics` exports `allure_funding_contributions{provider,tier,status}`
  (counts only, Snapshot-cached; `METRICS.md` privacy negatives apply) and
  its `Metrics::Catalog` entry points at `/admin/funding`.

## 8. Environment

| variable | meaning |
|---|---|
| `FUNDING_ENABLED` | master switch, off by default; while unset the whole feature is invisible and badges are not rendered, whatever else is configured |
| `FUNDING_LINK_COFFEE` / `_BEER` / `_ENERGY` | static checkout links, any provider, manual granting |
| `FUNDING_STRIPE_LINK_<TIER>`, `FUNDING_STRIPE_PRICE_<TIER>`, `FUNDING_STRIPE_WEBHOOK_SECRET`, `FUNDING_STRIPE_SECRET_KEY` | the Stripe provider; enabled only with the API key, webhook secret and at least one verified annual subscription link+price pair |
| `FUNDING_HELLOASSO_CLIENT_ID`, `_CLIENT_SECRET`, `_ORG_SLUG`, `FUNDING_HELLOASSO_FORM_<TIER>` | the HelloAsso provider |

All read through `Allure::Funding::Config` at call time, all absent by
default, all documented in `docs/site/configuration/environment.md` in the
same patch (guard spec), with an operator page describing the Stripe and
HelloAsso setup end to end.

## 9. Spec coverage

- Model: tier/status constraints, invoice and subscription identity uniqueness,
  paid-period boundaries (including future starts), manual rolling expiry,
  highest-active-tier resolution, deletion cancellation/purge and export content.
- Annual lifecycle: first paid invoice, paid renewal, cancellation scheduled
  and immediate cancellation, failed renewal then retry, early/late payments,
  leap-year boundaries, duplicate and reordered invoice/checkout events,
  reconciliation after initial reference expiry, renewal after cancellation,
  and no grants from checkout/status/trial/zero-value/proration events. A future
  paid period never grants early; a paid historical period never grants today.
- Portal: ownership, customer-id injection refusal, CSRF on session creation,
  fixed return URL, no URL logging/storage, no iOS controls, and the master
  switch warning that disabling Allure does not cancel provider billing.
- Helper: badge rendered only while `FUNDING_ENABLED` is set, for an active,
  non-hidden contribution; never for remote actors; palette validation;
  accessible name.
- Requests: `/funding`, the webhooks, `/admin/funding` and the settings group
  all 404/absent while `FUNDING_ENABLED` is unset; `/funding` absent for
  `hotwire_native_app?`; webhook 404 for unknown/disabled provider, rejected
  on bad signature **before** body parsing, idempotent on redelivery,
  unmatched on a bad reference; admin mutations audited and operator-only.
- Providers: the `a funding provider` shared examples; the Stripe HMAC vectors;
  the HelloAsso read-back on pinned cassettes (WebMock, no live calls).
- Guards: env documentation spec, metrics catalog spec, locale completeness
  (five languages), i18n of every tier name and badge copy.

## 10. Deferred

- HelloAsso automation: annual automatic renewal and cancellation support
  must be verified against the provider's current API and eligible form types
  before the adapter is offered.
- A `funding_expiring` reminder notification about two weeks before expiry.
- An anonymous supporter count on the operator dashboard.
