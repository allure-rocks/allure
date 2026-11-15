# Access contract — public means registered

Viewing anything on an Allure instance requires a registered account. This
document is the access contract: which surfaces a browser visitor may reach,
how the application distinguishes a visitor from a protocol peer, and why the
ActivityPub wire contract is unchanged. `DESIGN.md` governs the visuals; where
the two conflict on a data or protocol contract, this document wins.

## 1. The rule

Anonymous visitors never see a publication, a course, a profile, or derived
media. "Public" keeps its federated meaning — the publication may still be
distributed to peers and their accounts — but on the origin instance every
reader is signed in. A visitor who opens a shared link is redirected to the
sign-in page and lands back on the requested page once authenticated.

Registration stays governed by `ALLOW_REGISTRATION` (`Allure::Registration`):
the operator decides how accounts are obtained, not whether viewing them
requires one.

## 2. Browser surfaces

| Surface | Anonymous browser |
|---|---|
| `/` root dispatcher | redirect to sign-in |
| `/feed` personal stream and Public switch | redirect to sign-in |
| `/workouts/:id`, owner media and analysis endpoints | redirect to sign-in |
| `/publications/:id/media/{gpx,route-image}` (browser) | redirect to sign-in |
| `/segments/:id`, leaderboard, efforts, track, chart, route image | redirect to sign-in |
| `/@username`, `/@username/avatar` | redirect to sign-in |
| `/@handle`, `/@handle/avatar` (remote profiles) | redirect to sign-in |
| `/remote_notes/:id`, `/remote_segments/:id` | redirect to sign-in |
| Sign-in, registration, password reset | public |
| Error pages, PWA manifest, health check, `/metrics` (token), styleguide (dev) | public |

The redirect uses `Authentication#request_authentication`:
`session[:return_to_after_authenticating]` stores the requested URL and
`after_authentication_url` returns to it. A shared federated link therefore
survives the sign-in gate.

## 3. Principals

`Workouts::PublicationPrincipal` distinguishes the origins so a policy can
never mistake a visitor for a peer:

| Factory | Kind | Meaning |
|---|---|---|
| `anonymous` | `:anonymous` | browser visitor with no session |
| `browser(user)` | `:browser_user` | signed-in local account |
| `browser(nil)` | `:anonymous` | fail-closed default |
| `protocol(nil)` | `:protocol_anonymous` | unsigned ActivityPub fetch |
| `protocol(actor)` | `:remote_actor` / `:local_actor` | verified signer |

## 4. Policies

`Workouts::PublicationPolicy` and `Segments::PublicationPolicy` answer a public
publication:

- `:browser_user`, `:protocol_anonymous`, `:remote_actor` → allowed;
- `:local_actor` → owner only (unchanged);
- `:anonymous` → denied;
- followers audience: unchanged (owner, accepted local follower, promoted
  accepted remote follower while restricted federation is enabled).

`Workout#viewable_by?` follows the policy, so `nil` is denied.
`Segment#viewable_by?` serves a public course only to a present viewer
(`viewer.present?`). `Workout.visible_to(nil)` and `Segment.visible_to(nil)`
return nothing.

## 5. Federation boundary

Public wire access is deliberately unchanged: remote instances have no Allure
account, and federation cannot verify one. The following stay reachable
without a session and keep serving only active public publications:

- `GET /api/v1/trail/:id`, `/api/v1/trail/:id/media/*`;
- `GET /api/v1/segment/:id`, `/api/v1/segment/:id/media/*`;
- the actor's public outbox page and its public activities;
- WebFinger, NodeInfo, the actor document, followers/following collections.

Followers-only objects and media keep requiring a verified signed request and
the existing entitlement rules. This document does **not** introduce
authorized fetch: an anonymous protocol client that knows a public
publication's ShortUUID can still read its JSON and media. The member-facing
copy says "public means a registered account" for the browser surfaces, not
for the protocol; closing that gap would break interop with peers that do not
sign public GETs and is a separate decision.

## 6. Consequences in the design reference

- `DESIGN.md` §8.1/§8.3: `/` sends visitors to sign-in; the feed is
  members-only; the visitor intro card is removed.
- `DESIGN.md` §7.5: the footer version line renders on the members' shared
  layout; auth and error pages keep their own minimal chrome.
- `DESIGN.md` §10.17: only the owner reads counts without a gesture; a
  signed-in non-owner gets the toggle buttons.

## 7. Verification

Request specs prove the redirect for every browser surface and the
post-authentication return; policy specs prove the `:anonymous` denial and the
`:protocol_anonymous` allowance; the signed protocol specs (public Note,
course object, media, outbox) stay green. `dip fed_test` and
`dip fed_restricted_test` keep the federation contract honest.
