# Instance funding

An operator may invite members to contribute voluntarily to the cost of hosting
their instance. Contributions unlock no features. A coffee, beer or energy-drink
badge identifies the tier, with a colour the account chooses; the account may
also hide it. The badge is local and never changes the avatar image or federates.

An automated contribution is an **annual subscription with automatic renewal**.
Each verified paid invoice grants its own billed period; cancelling stops
renewal but leaves the already paid badge in place. Allure stores no banking
details, does not process or refund payments, and never locks any feature
behind a contribution. Your provider's terms, fees, eligibility and any
applicable accounting or tax duties remain your responsibility.

## Enable it

Set `FUNDING_ENABLED=true` in `.env.production`, then recreate the web and
worker containers using your ordinary deployment workflow. The account menu on
the web links to `/funding`.

## Manual checkout links (any provider)

Optionally set `FUNDING_LINK_COFFEE`, `FUNDING_LINK_BEER` and
`FUNDING_LINK_ENERGY` to hosted HTTPS checkout pages from your payment
provider. An unconfigured tier has no payment button. Check the received
payment, then open the member's page in **Administration → Accounts** and
record a year of support at the corresponding tier. A manual grant starts at
its confirmation time and never renews automatically.

## Stripe subscriptions

For each tier, create a **subscription Payment Link** in your Stripe dashboard
with exactly one recurring price, `interval: year`, `interval_count: 1`,
quantity 1 — no trial, prorations, instalments or additional products. Then set
its link and price id:

```text
FUNDING_STRIPE_LINK_COFFEE=https://buy.stripe.com/…
FUNDING_STRIPE_PRICE_COFFEE=price_…
```

and the instance's server-side API key and webhook secret:

```text
FUNDING_STRIPE_SECRET_KEY=sk_live_…
FUNDING_STRIPE_WEBHOOK_SECRET=whsec_…
```

The Stripe provider is active only when the API key, the webhook secret and at
least one complete link+price pair are present. Allure appends
`?client_reference_id=<signed reference>` to the hosted link, verifies
`POST /funding/webhooks/stripe` with the `Stripe-Signature` HMAC, and grants a
badge from the **verified annual invoice line**, never from checkout
completion. Configure each Payment Link's after-payment redirect to
`https://<your-instance>/funding/thanks`.

The customer portal offers cancellation at period end, payment-method updates
and invoices. Members open it from `/funding` with **Manage my subscription**;
cancelling stops renewal but leaves the already paid badge in place. Account
deletion stops future renewals through the API before its billing identifiers
are purged.

`bin/rails funding:reconcile` replays paid invoices if a webhook was lost or
reordered; a daily recovery job replays the last month. Idempotent recording
makes a replay harmless. Set `SINCE=YYYY-MM-DD` to recover older invoices.

## Confirm payments manually (other providers)

With hosted payment pages or another provider, check the received payment, then
open the member's page in **Administration → Accounts** and record a year of
support at the corresponding tier. A manual grant starts at its confirmation
time and never renews automatically. The member receives a notification.

**Administration → Contributions** lists the history, allows audited
revocation, and can attach an **unmatched** subscription to an account when its
checkout reference expired before the webhook arrived. Revoking a badge does
not refund money. The account's data export includes its contribution dates and
tiers, but no provider payload. Account deletion removes its contributions and
stops its future renewals.

## Disable it completely

Unset `FUNDING_ENABLED` or set it to `false`, then recreate the affected
containers. Payment pages, navigation, settings and administration controls
disappear; badges disappear too. Data is retained. Re-enabling restores badges
whose contribution period has not ended. Disabling Allure's feature does **not**
disable payment links or subscriptions at the external provider: stop renewals
there first if needed. Account deletion always stops the deleted account's
future renewals, whatever the switch.

## iOS companion

The companion displays badges but has no funding page, payment link, badge
settings, portal control or funding administration controls. Those are
web-only. This separation is not a guarantee of App Store acceptance; review
current store rules before shipping any monetisation change.
