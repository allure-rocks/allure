# API contract

Allure's programmatic surface for an account's own clients — scripts,
automations, dashboards, a watch-to-Allure bridge — as three parts that ship
together and stay in sync:

1. a versioned **REST API** under `/api/rest/v1`, authenticated by **API
   tokens** (scoped bearer tokens);
2. outgoing **webhooks**: signed HTTP notifications of account events, sent to
   URLs the account chooses;
3. one hand-written **OpenAPI 3.1 document** that describes both (its `paths`
   and its `webhooks`), validated by the test suite and rendered for members
   by an embedded **Scalar** reference at `/developers/api`.

## 1. Scope and non-goals

In scope: reading an account's workouts and derived data, importing files,
editing and deleting workouts, publishing through publishing profiles, reading
the social surfaces the web already shows the account (feed, comments,
reactions, follows), and webhooks for workout, publication, record, segment and
social events.

Not in scope, deliberately:

- **OAuth 2 / third-party applications.** API tokens are created by the
  account itself. OAuth (authorization code + PKCE, registered applications) is
  a later contract; §15 lists what this one reserves for it.
- **AI assistants.** The Model Context Protocol endpoint (`POST /mcp`) is its
  own contract, `[devdoc:mcp]`. It reuses this contract's token boundary
  (§4.5, §4.6) and serializers, needs the `read` scope, and adds one column to
  `api_tokens` (`mcp_geometry`, the token's location level for assistants).
- **Federation.** The ActivityPub surfaces (`/api/v1/trail|segment|comment`,
  actors, inboxes) are unchanged. The REST API never emits or accepts an
  ActivityPub document and is never a federation channel.
- **Operator powers.** No `/admin` capability is reachable with a token, even
  the operator's.
- **Browser cross-origin access.** No CORS headers in v1; tokens are meant for
  server-side clients. The reference page is same-origin.
- **Health data** beyond what a workout file already carries
  (`REMOTE-IMPORTS.md`).
- **Account management**: password, two-step verification, identity providers,
  sessions, tokens themselves and account deletion are web-only.

## 2. Privacy invariants

The API is a second door onto the same rooms, never a new room.

1. **Owner data is the owner's.** A token reads and changes only its account's
   own rows, every query scoped through the token's user exactly as the web
   controllers scope through `current_user`. A foreign or unknown identifier
   answers 404, never 403.
2. **Other accounts' data goes through the reader's door.** Another account's
   workout is reachable only as a *publication*, resolved by
   `Workouts::PublicationResolver` / `WorkoutPublication.visible_to` and
   rendered from its sanitized snapshot; a received note only through the
   account's entitlements (`Federation::FollowingFeed`,
   `Federation::RemoteNotePolicy`). The API never projects another account's
   `Workout`, track, original file, places, anomalies or detected laps.
3. **Nothing the web hides appears here.** Every reader-side field is one the
   corresponding web page renders for the same account. Owner-only
   derivations (detected laps, places, anomalies, personal places, best
   efforts) stay owner-only.
4. **Webhooks carry summaries, not geometry.** A webhook payload never
   contains coordinates, a track, an original file, a route image or another
   account's private field; it carries identifiers, summary figures and links
   the receiver fetches with a token (§11.4).
5. **Members-only holds.** Every endpoint, the OpenAPI document and the
   reference page require a signed-in account or a valid token (`ACCESS.md`).
   Nothing here is anonymous.
6. **Secrets are shown once.** Token secrets and webhook secrets are displayed
   once at creation (and at webhook-secret rotation), stored only as a digest
   (tokens) or encrypted (webhook secrets), and never logged. A copy kept for
   a replay (the `Idempotency-Key` store, §5) is encrypted too.

## 3. Namespace and versioning

- Base path: **`/api/rest/v1`**. `/api/v1` already names the ActivityPub
  object routes (`/api/v1/trail/:id`, `/api/v1/segment/:id`,
  `/api/v1/comment/:id`); a REST `/api/v1/segments` beside the federation
  `/api/v1/segment/:id` would be a lasting source of confusion.
- `servers[0].url` in the served document is derived from
  `Allure::Federation::Config` (scheme, host, port) at request time; the YAML
  never hardcodes a host.
- Within v1, changes are additive only: new endpoints, new optional request
  fields, new response fields, new enum values clients must tolerate (every
  enum in the document is declared open with a note). Removing or retyping a
  field, or changing a unit, needs `/api/rest/v2`.
- `info.version` is the application version (`Allure::VERSION`, as NodeInfo
  reports it), so a client can tell which additions an instance carries.

Routes live in their own `namespace :api { namespace :rest { namespace :v1 } }`
block in `config/routes.rb`; controllers under
`app/controllers/api/rest/v1/`, representations under
`app/serializers/api/rest/v1/` (plain Ruby objects returning hashes, no
serializer gem).

## 4. API tokens

### 4.1 Model

`api_tokens`:

| column | meaning |
|---|---|
| `user_id` | owner, cascade on account deletion |
| `name` | the account's label, 1–80 characters |
| `token_prefix` | the first 12 characters of the token (`allure_pat_X`), shown in lists |
| `token_digest` | SHA-256 hex of the full token, unique index |
| `scopes` | string array, non-empty, check constraint on the allowed values |
| `expires_at` | NOT NULL; at most 365 days after creation |
| `last_used_at` | refreshed at most every 5 minutes |
| `revoked_at` | NULL while usable |
| `revoked_by` | `owner` / `operator` / `system` (NULL while usable) |

At most **20 unrevoked tokens per account** (model validation and service
check). Revoked and expired rows are kept 90 days for the security list, then
pruned by the existing daily session-pruning sweep's sibling
(`ApiTokens::PruneJob`).

### 4.2 Format

`allure_pat_` followed by 43 characters of URL-safe Base64 (32 random bytes).
The fixed prefix lets secret scanners and the account recognise a leaked
token. A SHA-256 digest is sufficient for a 256-bit random secret; no slow
hash is used, so lookup is a single indexed equality.

### 4.3 Scopes

| scope | grants |
|---|---|
| `read` | the account's own workouts, derived data, records, equipment, publishing profiles, import batches |
| `write` | editing and deleting the account's workouts (implies nothing else) |
| `import` | creating import batches and reading them |
| `publish` | previewing, creating, rescheduling, activating, withdrawing and cancelling publications |
| `social:read` | the feed, readable publications and received notes, comments, reactions, followers and following |
| `webhooks` | managing the account's webhook endpoints and reading their deliveries |

Scopes never imply each other: `write` without `read` can PATCH but not list.
The document declares each operation's scope as an `x-allure-scope` extension
and in its `security` requirement; a missing scope answers 403
`insufficient_scope` naming the scope.

### 4.4 Lifecycle and UI

- Created and revoked only from `/settings/api` (`DESIGN.md` §20.18). Creation
  requires a recent authentication (`require_recent_authentication`, the
  10-minute window of `AUTH.md`); the form asks a name, the scopes (none
  pre-ticked) and an expiry (30 / 90 / 365 days, default 90).
- The secret is rendered once, on the page that follows creation, with a copy
  button; reloading the page never shows it again.
- Creation and revocation send a `SecurityMailer` message, like the other
  security changes.
- The operator revokes any account's tokens from the « API » tab of
  `/admin/accounts` (audited `api_token_revoked`), never seeing a secret.

### 4.5 Request authentication

`Api::Rest::V1::BaseController < ActionController::API` reads only
`Authorization: Bearer <token>`. It never reads the session cookie, so no API
mutation is reachable by a cross-site request and CSRF does not apply. The
one exception is the OpenAPI document (§12), which also accepts a signed-in
session.

A token is refused with **401** (`WWW-Authenticate: Bearer`) when it is
missing, malformed, unknown, revoked or expired, and with **403** when:

| code | when |
|---|---|
| `account_suspended` | the account is suspended |
| `second_factor_required` | `Auth::SecondFactorPolicy` puts the account in enrolment-only state (past its grace period without a factor) |
| `insufficient_scope` | the operation's scope is not on the token |

`Current.api_token` and `Current.user` are set for the request; no `Session`
row is created and `sessions.last_seen_at` is untouched.

### 4.6 Rate limits

Rails' `rate_limit`, as `SessionChallengesController` and the comment
controllers already use it, keyed by the token id:

| bucket | limit |
|---|---|
| every request | 300 per minute |
| mutations (`POST`/`PATCH`/`DELETE`) | 60 per minute |
| `POST /imports` | 20 per hour |

A refusal is **429** with `Retry-After` and the `rate_limited` problem code.
The limits are best-effort per cache store, as for the existing limits; they
protect the instance, not a billing contract. The first two buckets are one
per token across every controller behind the boundary, `/mcp` included
(`rate_limit ... scope:`; Rails' default would count per controller path).

`POST /imports` also goes through the web's database-counted admission
(`IMPORT-SOURCES.md`): past 3 file imports or 1 Strava archive waiting, or
6 GB uploaded in 24 hours, it answers **429** `import_limit` with a `reason`
(`too_many_active_imports`, `archive_in_progress`, `upload_budget_exceeded`)
and a `Retry-After`, and stores nothing.

## 5. Conventions

- **Media type**: `application/json; charset=utf-8` for every response except
  the original-file download and the GPX/GeoJSON exports; requests are JSON
  except `POST /imports` (`multipart/form-data`).
- **Errors**: RFC 9457 `application/problem+json` —
  `{ type, title, status, code, detail, errors? }`. `type` is
  `https://<instance>/developers/api#problem-<code>`; `code` is the stable,
  machine-readable value clients branch on; `errors` lists field errors as
  `{ field, code, detail }` for 422. `title` and `detail` are English
  (§13.3).
- **Identifiers**: workouts and publications use their existing ShortUUID
  public ids; segments, equipment, profiles, batches, tokens, webhook
  endpoints and deliveries use their own public ids (ShortUUID for new
  tables). Bigint primary keys never appear.
- **Units**: SI exactly as persisted (`WORKOUT.md`): metres, seconds, m/s,
  bpm, rpm, watts, joules. Pace is never pre-computed; a sport's
  `pace_basis_metres` is exposed so the client can. The account's unit system
  does not change the API.
- **Time**: RFC 3339 with offset, UTC (`Z`). Durations are integer seconds.
- **Coordinates**: GeoJSON `[longitude, latitude]` (and elevation as a third
  value where present), the repository convention.
- **Pagination**: opaque cursor. `?limit=` (1–100, default 25) and
  `?cursor=`; responses are `{ data: [...], next_cursor: "…" | null }`.
  Cursors encode the sort key and id, signed so they cannot be forged.
- **Sport**: the slug (`cycling_gravel`), never a translated label;
  `GET /sports` gives the labels in both locales.
- **Idempotency**: every `POST` accepts `Idempotency-Key` (1–255
  characters). The first response is stored 24 hours per
  `(token, key)` in `api_idempotency_keys`; a replay returns it with
  `Idempotency-Replayed: true`, and the same key with a different body answers
  422 `idempotency_key_reused`. The stored body is encrypted at rest
  (`encrypts :response_body`): a webhook creation or secret rotation keeps
  the secret it showed once, and the column must not hold it in clear.
- **Conditional reads**: `ETag` on single-resource GETs, `If-None-Match` → 304.
- **Locale**: none. Enum values are stable codes; labels come from
  `GET /sports` and the reference.

## 6. Resources and endpoints

All paths are relative to `/api/rest/v1`. Scope in brackets.

### 6.1 Account and catalog

| method & path | scope | notes |
|---|---|---|
| `GET /me` | any | username, display name, handle, locale, unit system, time zone, avatar URL (application endpoint), the heart-rate profile, the token's scopes and expiry |
| `GET /sports` | any | the 36 slugs, family, `virtual`, `pace_basis_metres`, labels `{fr, en}` |

### 6.2 Workouts (owner)

| method & path | scope | notes |
|---|---|---|
| `GET /workouts` | read | filters mirroring `/workouts`: `sport`, `from`, `to` (start date), `commute`, `equipment`, `place`, `q`; `sort` = `-started_at` (default), `started_at`, `-distance`, `-duration` |
| `GET /workouts/{id}` | read | the `Workout` representation (§7.1) |
| `GET /workouts/{id}/track` | read | GeoJSON `FeatureCollection`, one `LineString` feature per recording segment, with parallel per-point arrays (`times`, `heart_rates`, `cadences`, `powers`, `speeds`) in `properties` when recorded; never joined across gaps |
| `GET /workouts/{id}/original` | read | the original file, as the owner web download |
| `GET /workouts/{id}/laps` | read | recorded laps and detected laps, each with `source` |
| `GET /workouts/{id}/splits` | read | `?distance=` metres (default 1000) |
| `GET /workouts/{id}/best_efforts` | read | |
| `GET /workouts/{id}/segment_efforts` | read | with the viewer's personal place and leaderboard rank |
| `GET /records` | read | classic records and best-effort records per sport |
| `GET /equipment`, `GET /equipment/{id}` | read | |
| `GET /publishing_profiles` | read | id, name, audience, delay, automatic, publishable |

### 6.3 Writes and imports

| method & path | scope | notes |
|---|---|---|
| `PATCH /workouts/{id}` | write | `title`, `description`, `notes`, `sport`, `commute`, `equipment_ids` — the web edit form's fields; a sport change marks the import entry `manual` exactly as the web does (`VIRTUAL-PLATFORMS.md`) |
| `POST /workouts` | write | a manual entry (`[devdoc:manual-entry]`): `sport`, `started_at` (ISO 8601 with an offset) and `elapsed_time` required, the optional figures in SI, the text fields, `commute`, `equipment_ids`; `Workouts::ManualEntry`, **201** with the workout and a `Location`, `Idempotency-Key` honoured. A manual entry's `PATCH` also takes its figures; a recording's figure is `not_editable` |
| `DELETE /workouts/{id}` | write | `Workouts::WorkoutDeletion`, the same cascade as the web (live publications are deleted and federated `Delete`s sent; a scheduled one is cancelled). 204 |
| `POST /imports` | import | multipart `files[]` (GPX, FIT, TCX, KML, ZIP, single-file GZIP, the web limits), optional `fallback_sport`. Creates a `WorkoutImportBatch` with `source: "file"` and the new `trigger: "api"`; answers **202** with the batch and a `Location`. With `source=strava_archive`: exactly one Strava archive `.zip` (2 GB), `fallback_sport` optional, `notes` ignored, run by `Workouts::StravaArchiveImportJob` (`[devdoc:strava-archive]`) |
| `GET /imports`, `GET /imports/{id}` | import or read | batch state, counters and entries (`status`, `skip_reason`, `workout_id` once imported) |
| `DELETE /imports/{id}` | import | cancels a running batch, as the web's cancel |

API imports follow the ordinary import pipeline, deduplication and automatic
publishing rules; a batch over 5 entries is bulk (`AUTO-PUBLISHING.md`).

Import details:

- `fallback_sport` is **required** for files, as on the web form: a GPX file
  often records no sport, and a silent default would mislabel it. A missing
  or unknown slug is a `validation_failed` field error. A Strava archive's
  activities name their own type, so it is optional there.
- Each file is a multipart part named `files[]` (the Rails convention; a
  repeated `files` part keeps only the last). The document names the parsed
  property `files`, which is what the contract validator sees.
- `PATCH` is the only update verb; `PUT` is not routed. Unknown fields, wrong
  types, an unknown sport and another account's equipment are each a
  `validation_failed` field error (`unknown`, `invalid_type`, `unknown_sport`,
  `unknown_equipment`, `not_editable` for a recording's measured figure,
  `required` for a manual entry's missing sport, start or elapsed time), and
  nothing changes. A failed re-analysis is `sport_change_failed`, rolled back
  with the rest of the request.
- Cancelling a finished import is **409** `import_finished`.
- Idempotency (§5): a key is claimed after authorization and the scope check,
  so a refused token keeps nothing; a 5xx or 429 is not kept; a retry while
  the first request runs is **409** `idempotency_key_in_progress`. The
  fingerprint is the method, path, query and body, an uploaded file counting
  by its name and its bytes' SHA-256.
- Import batches have a ShortUUID (`workout_import_batches.uuid`); the web
  import page and `/admin/imports/:id` use it in their URLs too.
- `GET /workouts/{id}/splits?distance=` accepts 100–100 000 metres. A row
  carries `average_power` when the recording recorded power, the same sample
  mean as the recorded and detected laps.

### 6.4 Publication

| method & path | scope | notes |
|---|---|---|
| `GET /workouts/{id}/publications` | read | live and scheduled publications (`PUBLISHING.md`: at most one per audience) |
| `POST /workouts/{id}/publication_previews` | publish | `{ publishing_profile_id }` → the readiness the web's preview shows: `publishable`, refusals, and the shared / not-shared lists (§7.4) |
| `POST /workouts/{id}/publications` | publish | `{ publishing_profile_id, delay, acknowledge }` |
| `POST /publications/{id}/activation` | publish | publish a scheduled publication now |
| `PATCH /publications/{id}` | publish | `{ delay }` — reschedule a scheduled publication to another preset from now |
| `DELETE /publications/{id}` | publish | delete an active publication (federated `Delete`) or cancel a scheduled one |

`acknowledge` must be `true`: it is the API's equivalent of reading the
§19.1/§19.2 copy before pressing Publish, and its absence answers 422
`acknowledgement_required` whose `detail` carries the §19.2 English sentence.
`delay` is `profile` (default: the profile's delay) or one of the
`PublishingProfile::PUBLISH_DELAYS` keys (`immediate`, `1_day`, `3_days`,
`1_week`, `2_weeks`, `1_month`). Everything else — privacy-zone preparation,
fail-closed refusals, route-image readiness, replacement of the same audience
— is `Workouts::Publisher` and `Workouts::PublicationReplacement` unchanged.
Course publications stay web-only in v1.

Publication details:

- `PATCH` takes a `delay` counted from now, because
  `Workouts::ScheduledPublicationReschedule` moves a publication between
  presets, never to an arbitrary instant.
- `POST /workouts/{id}/publications` on an audience that already has a live
  publication replaces it (the web's Republish); an audience with a
  *scheduled* publication is refused.
- Every refusal of the services is **422** `publication_refused` with a
  `reason` member: `Workouts::Publisher::PublicationError` and
  `PublicationCandidate::PreparationError` carry a `code` beside their
  translated message (`privacy`, `endpoint_mask`, `route_unavailable`,
  `actor_unavailable`, `followers_unavailable`, `already_published`,
  `already_scheduled`, `audience_taken`, `invalid_delay`). Activating or
  rescheduling a publication that is no longer scheduled is **409**
  `not_scheduled`.
- The preview answers from `Workouts::PublicationReadiness` (no projection is
  built): its codes become `refusals` when it is not ready and `warnings`
  when it is. `copy` carries the §19.1 shared and never sentences and the
  §19.2 irrevocability sentence, in English.
- Publications are reached by their own ShortUUID, among the account's
  active and scheduled ones; a deleted publication is a 404.

### 6.5 Social, read-only

| method & path | scope | notes |
|---|---|---|
| `GET /feed` | social:read | `?public=true` mirrors the web switch; items are `publication` or `remote_note` (§7.3), newest-publication-first, cursor-paginated |
| `GET /publications/{id}` | social:read | a local publication readable by the account, at the narrowest audience the resolver serves it |
| `GET /remote_notes/{id}` | social:read | an entitled received note |
| `GET /publications/{id}/comments`, `GET /remote_notes/{id}/comments` | social:read | the thread the web shows the account for that publication |
| `GET /workouts/{id}/comments` | social:read | the owner's view of their workout's threads (`?audience=`) |
| `GET /workouts/{id}/reactions` | social:read | counts per type; the reacting accounts as the owner's web view lists them |
| `GET /followers`, `GET /following` | social:read | accepted relationships, local and remote, with handle, display name, avatar URL |

Writing comments, reacting and following stay web-only in v1.

Social details:

- Every read acts as the token's account in a signed-in browser
  (`Workouts::PublicationPrincipal.browser`), through
  `Federation::FollowingFeed`, `Workouts::PublicationPolicy`,
  `Federation::RemoteNotePolicy`, `Comments::Listing` with
  `Workouts::ReadableAudiences`, `Comments::Counts` and
  `Reactions::Summaries` — the services the web pages call.
- `GET /feed` keeps the web's default: `public` is on when the account
  follows nobody; `true`/`false` force it. The cursor is the feed's own order
  (`published_at`, `kind`, `id`).
- `GET /publications/{id}` serves the publication named when the policy lets
  the account read it; the feed already picks the narrowest audience per
  workout. `GET /publications/{id}/comments` is that publication's audience
  thread only.
- The token cannot fetch the web's session-guarded media, so the API serves
  its own: `GET /publications/{id}/track` and `/route_image?theme=`, and the
  same two under `/remote_notes/{id}`, each behind the resource the policy
  names (`track`, `route_image`, `media`).
- Received notes have a ShortUUID (`remote_notes.uuid`) for the API only; the
  web keeps its `/remote_notes/:id` URLs.
- `GET /workouts/{id}/reactions` gives counts per type and the account's own
  reaction: the web names nobody who reacted, so the API does not either.
- An `Account` carries its handle, display name, whether it is local or
  deleted, and its profile URL on this instance. No avatar URL: avatars are
  served to signed-in browsers only.
- Comment text is the stored plain `body`; a received comment's HTML never
  leaves the instance. A withdrawn root kept for its replies is a stub with
  neither author nor text.

### 6.6 Webhook management

| method & path | scope | notes |
|---|---|---|
| `GET /webhooks`, `POST /webhooks` | webhooks | creation returns the secret once |
| `GET /webhooks/{id}`, `PATCH /webhooks/{id}`, `DELETE /webhooks/{id}` | webhooks | `url`, `description`, `events`, `active` |
| `POST /webhooks/{id}/ping` | webhooks | enqueues a `ping` event to this endpoint only |
| `POST /webhooks/{id}/secret_rotation` | webhooks | new secret returned once; the old one keeps signing for 24 h (§11.3) |
| `GET /webhooks/{id}/deliveries` | webhooks | last 30 days, newest first |
| `POST /webhook_deliveries/{id}/redelivery` | webhooks | a new delivery of the same event to the same endpoint |

## 7. Representations

Field lists are normative for v1 and mirrored in `components.schemas`.

### 7.1 `Workout` (owner)

`id`, `title`, `description`, `notes`, `sport`, `commute`, `started_at`,
`ended_at`, `distance`, `moving_time`, `elapsed_time`,
`ascent`, `descent`, `min_elevation`, `max_elevation`, `average_speed`,
`max_speed`, `average_heart_rate`, `max_heart_rate`, `average_cadence`,
`average_power`, `max_power`, `calories`, `device`, `places` (the up-to-three
display names), `equipment_ids`, `contested_metrics` and `plausible_values`
(the value of each contested figure without the anomaly),
`data_anomalies` (kinds and severity, no geometry), `analysis_version`,
`elevation_source`, `import` (`source`: `file` or the connection's provider;
`sport_source`), `publications` (id, audience, status, scheduled_for),
`created_at`, `updated_at`, and `links` (`self`, `track`, `original`, `web`).
A workout stores no time zone of its own; `GET /me` gives the account's.
The detail form also carries `heart_rate` (coverage, sampled and recorded
seconds, load, the five zones' bpm ranges and seconds; `null` without a usable
histogram, zones and load `null` without a profile), and `GET /me` the
account's `heart_rate_profile` (`HEART-RATE.md`).

Absent measurements are `null`, never `0`. The list endpoint returns the same
object without `description`, `notes`, `analysis_version`, `data_anomalies`,
`plausible_values`, `import`, `publications`, `weather` and `heart_rate`.

### 7.2 `Publication` (reader)

Built from the snapshot only: `id`, `audience`, `published_at`, `author`
(handle, display name, avatar URL), `sport`, `title`, `description` and the
metrics the profile shared, `device` / `commute` / `record_types` /
`record_distances` when shared, `comments_open`, `reaction_counts`, and
`links` (`web`, and `track` / `route_image` only when the snapshot carries
them, as application endpoints the token may fetch). A field the profile did
not share is **absent**, not `null`, so a client never mistakes "hidden" for
"not recorded".

### 7.3 `FeedItem`

`{ type: "publication" | "remote_note", own: boolean, publication | remote_note }`.
`RemoteNote` mirrors `Federation::RemoteNoteView`: the parsed Allure fields,
author handle, origin `url`, media state, never remote HTML.

### 7.4 `PublicationPreview`

`publishable`, `refusals[]` (codes), `audience`, `shared[]` and `not_shared[]`
(field codes, the lists the web lays out under §19.1), `delay`, and `copy`:
the English §19.1/§19.2 sentences for the client to show its user.

### 7.5 Other representations

`Comment`, `ReactionSummary`, `Account`, `Equipment`, `Record`, `BestEffort`,
`SegmentEffort`, `Lap`, `Split`, `ImportBatch`, `ImportEntry`,
`WebhookEndpoint`, `WebhookDelivery`: each mirrors its web card's columns; the
document is the field list of record. `Comment` carries `state` (`active`,
`deleted`, `removed`) and never the text of a deleted or removed comment,
exactly as the web.

## 8. Imports through the API

The upload is streamed to Active Storage exactly as the web form's batch
upload; the request returns once the batch row and its source blobs exist,
before any parsing. Enumeration, per-entry progress and deduplication are the
existing `Workouts::ImportBatchJob` pipeline. `trigger: "api"` is added to
`WorkoutImportBatch::TRIGGERS`, shown as « API » on `/workouts/import` and
`/admin/imports`, and counted in `allure_import_batches`.

## 9. Publication through the API

The API adds no publication semantics; it is a second caller of the same
services. The only API-specific rule is the explicit `acknowledge` (§6.4).
An account with an automatic profile is told nothing new: automatic publishing
already happens without confirmation, and its rules are the profile's.

## 10. Social reads

Every social endpoint calls the service the web page calls with the token's
user as viewer — `Federation::FollowingFeed`, `Workouts::PublicationResolver`,
`Federation::RemoteNotePolicy`, `Comments::Post.permission` for visibility of
threads — and renders a representation of what that page renders. A spec per
endpoint asserts the negative: a publication the account cannot read on the
web is a 404 here, and a followers publication disappears from the API the
moment restricted federation or the follow ends.

## 11. Webhooks

### 11.1 Model

`webhook_endpoints`:

| column | meaning |
|---|---|
| `public_id` | ShortUUID |
| `user_id` | owner, cascade |
| `url` | HTTPS URL, ≤ 2 048 characters; `http` only while `ALLOW_PRIVATE_IPS` is on (the local ring) |
| `description` | optional, ≤ 200 characters |
| `events` | non-empty string array of event types (§11.2), or `["*"]` |
| `secret` / `previous_secret` | encrypted (`encrypts`), `whsec_` + Base64 of 32 bytes |
| `previous_secret_expires_at` | end of the 24-hour rotation overlap |
| `active` | owner switch |
| `disabled_at`, `disabled_reason` | set by the system (`failing`, `gone`) or the operator (`operator`) |
| `consecutive_failures`, `first_failure_at` | failure bookkeeping |

At most **10 endpoints per account**.

`webhook_events` — one row per emitted event, the payload frozen at emission:

| column | meaning |
|---|---|
| `public_id` | `evt_` + ShortUUID, the `webhook-id` header and the envelope `id` |
| `user_id` | cascade |
| `event_type` | §11.2 |
| `dedupe_key` | unique per user (e.g. `workout.analyzed:<workout>:<analysis_version>`) |
| `payload` | the envelope's `data` |
| `occurred_at` | |

`webhook_deliveries` — one row per (event, endpoint) attempt chain:
`public_id`, `webhook_event_id`, `webhook_endpoint_id`, `status`
(`pending` → `succeeded` / `failed` / `abandoned`), `attempts`,
`next_attempt_at`, `last_status_code`, `last_error` (a code, never a remote
body), `last_attempt_at`, `succeeded_at`, `redelivery_of_id`.

Events and deliveries are pruned after 30 days. Nothing here enters a
snapshot, a representation of another account, or federation.

### 11.2 Event catalogue

Emission is a no-op unless the account has an active, enabled endpoint
subscribed to the type: no row is written for an account without webhooks.

| type | emitted when | `data` |
|---|---|---|
| `ping` | `POST /webhooks/{id}/ping` | `{ webhook_id }` |
| `workout.created` | `Workouts::Importer` persisted a workout (not for a duplicate) | `WorkoutSummary` |
| `workout.analyzed` | the import's enrichments settled, judged by the same checks as `Workouts::AutoPublicationReadiness`, once per `analysis_version` | `WorkoutSummary` |
| `workout.updated` | metadata, sport, commute or equipment changed by the owner (web, API or bulk operation) | `WorkoutSummary`, `changed[]` |
| `workout.deleted` | the workout is deleted | `{ id }` |
| `publication.activated` | a publication went live (immediate, scheduled, automatic) | `PublicationSummary` |
| `publication.withdrawn` | an active publication was deleted, replaced or withdrawn by the operator; a scheduled one was cancelled | `{ id, workout_id, audience, reason }` |
| `publication.auto_failed` | an automatic publication failed | `{ workout_id, audience, reason }` |
| `record.achieved` | a classic record or a best-effort record changed holder to this workout | `{ workout_id, sport, record_type | distance, value }` |
| `segment_effort.created` | matching created an effort | `{ workout_id, segment_id, elapsed_time, personal_place, rank }` |
| `comment.created` | a comment the account would be notified of (on their workout, or answering theirs) | `{ comment_id, workout_id | remote_note_id, author, reply_to_id }` — the text is fetched |
| `reaction.created` | a reaction on the account's workout | `{ workout_id, type, author }` |
| `follow.requested` / `follow.accepted` | as the notifications of the same kinds | `{ account }` |
| `participation.requested` / `participation.confirmed` | as the notifications of the same kinds | `{ participation_id, workout_id, kind, account }` |
| `import_connection.expired` / `import_connection.revoked` | as the notifications | `{ provider }` |

Social and connection events are emitted at the exact call sites that create
the matching `Notification` kind, independently of the account's
notification switches: subscribing an endpoint is the preference. A
notification withdrawn later (an undone follow) withdraws nothing already
sent.

`WorkoutSummary` is the `Workout` list representation without `description`
and `notes`; `PublicationSummary` is `{ id, workout_id, audience,
published_at, links }`. Neither carries geometry.

Event details:

- An endpoint may subscribe only to the types Allure emits
  (`WebhookEndpoint::EVENT_GROUPS`), or `*`.
- The social and connection events (`follow.*`, `reaction.created`,
  `comment.created`, `participation.requested`/`confirmed`,
  `import_connection.*`) are emitted by `Notifications::Create` itself,
  before the recipient's in-app switch is read: subscribing an endpoint is
  the preference. One event per subject (`<type>:<class>:<id>` dedupe key).
  The detection suggestion has no event. A comment event names the comment,
  never its text.
- `record.achieved` fires from `Records::RecomputeService` when a record's
  holder changes (a new row or another workout), for the classic types and
  the standard distances; a recompute that keeps the holder announces
  nothing.
- `segment_effort.created` fires from `Segments::MatchWorkoutJob` for the
  efforts it creates, only for a workout created in the last 7 days, so a
  matcher upgrade or a backfill does not announce old outings. It carries
  the personal place and, when ranked, the leaderboard rank.
- Participations have a `uuid` (ShortUUID in payloads).

### 11.3 Envelope and signature

The body is

```json
{ "id": "evt_…", "type": "workout.analyzed", "created_at": "…Z",
  "api_version": "v1", "data": { … } }
```

and signing follows **Standard Webhooks**: headers `webhook-id`,
`webhook-timestamp` (Unix seconds) and
`webhook-signature: v1,<base64 HMAC-SHA256(secret, "<id>.<timestamp>.<body>")>`,
the secret being the Base64-decoded part after `whsec_`. During a rotation
overlap the header carries both signatures, space-separated. Receivers can use
any Standard Webhooks library; the document's `webhooks` section states the
algorithm and a 5-minute tolerance recommendation.

`User-Agent: Allure-Webhooks/<version> (+<instance base URL>)` and
`Content-Type: application/json`.

### 11.4 Delivery

- `Webhooks::DeliverJob` on a new **`webhooks`** Solid Queue queue (added to
  the default worker's queue list), concurrency-limited to 2 per endpoint.
- Transport is `Federation::Transport::Client` with its `SsrfGuard`
  unchanged: the URL is validated at creation, on every update, and its
  resolved address re-checked at every attempt (no DNS-rebinding window);
  redirects are **not** followed for webhooks (a 3xx is a failure); 10 s read,
  15 s total, response body read up to 4 KiB and discarded.
- 2xx is success. `410 Gone` disables the endpoint at once (`gone`).
- Retries: 1 min, 5 min, 30 min, 2 h, 6 h, 12 h after the first attempt
  (≈ 21 h), then `abandoned`.
- An endpoint whose deliveries have all failed for 3 days and at least 20
  times in a row is disabled (`failing`); the owner gets the new
  `webhook_disabled` notification (switch `users.notify_webhooks`, on by
  default) and re-enables it from the settings or `PATCH active: true`.
- Order is not guaranteed; clients order by `created_at` and deduplicate by
  `id`. Delivery is at least once.

Delivery details:

- Emission (`Webhooks::Emit`) runs after the surrounding commit
  (`ActiveRecord.after_all_transactions_commit`), so a rolled-back fact
  announces nothing; `Webhooks::Events` holds one emitter per type and
  reports, never raises, its own errors. Call sites: `Workouts::Importer`
  (`created`), `AutoPublishJob.nudge` (`analyzed`, with
  `AutoPublicationReadiness`), the web and API edits and the bulk commute,
  equipment and sport changes (`updated`, one event per workout, `changed`
  ignoring blank-to-blank), `WorkoutDeletion` (`deleted`),
  `ScheduledPublicationActivation` (`activated`), `PublicationWithdrawal`,
  `PublicationReplacement` and `ScheduledPublicationCancellation`
  (`withdrawn`, reasons `deleted`, `replaced`, `cancelled`, `operator`,
  `workout_deleted`), `AutoPublisher#fail!` (`auto_failed`).
- Transport keeps `Federation::Transport::Client` and its `SsrfGuard`; the
  client gained a `max_redirects:` keyword (default unchanged), which
  webhooks set to 0. Responses are read up to 64 KiB (a larger one is a
  `response_too_large` failure, not a silent success).
- The retry delays count from each failed attempt: 1 min, 5 min, 30 min,
  2 h, 6 h, 12 h (about 21 h in all), then `abandoned`. An attempt leases its
  delivery for 2 minutes under a row lock, so the recovery sweep
  (`Webhooks::RecoveryJob`, every 5 minutes, which also prunes after 30 days)
  never doubles an attempt.
- Disabling (`gone`, `failing`) abandons what was waiting.
- `ping` and redelivery need a deliverable endpoint (409 `webhook_inactive`).
- The settings page reveals a secret once after creation or rotation through
  a session flag holding only the endpoint id; the secret itself stays in the
  encrypted column.
- `WebhookEndpoint#disable!` sends `webhook_disabled` (reasons `gone`,
  `failing`, `operator`; switch `users.notify_webhooks`, shown on
  `/settings/notifications` once the account has an endpoint); re-enabling or
  deleting the endpoint withdraws it, so a later disabling notifies again.
- The operator acts from the « API et webhooks » card of
  `/admin/accounts/:id` (`Admin::ApiAccessController`); `/admin/jobs` lists
  the `webhooks` queue from Solid Queue with no change.
- `allure_api_requests_total` is a Yabeda counter fed by
  `process_action.action_controller` for `Api::Rest::V1::*`; `scope` is the
  first scope the operation requires, `any` before one is checked
  (an unauthenticated request, the document).

### 11.5 Lifecycle

Account suspension stops emission and pauses pending deliveries; account
deletion cascades. Deleting an endpoint abandons its pending deliveries.
The operator sees endpoints (host only, never the full URL path nor a secret)
and can disable one, audited `webhook_endpoint_disabled`.

## 12. The OpenAPI document

- Source of record: **`docs/openapi/v1.yaml`**, OpenAPI **3.1**, hand-written,
  English, split with `$ref` into `docs/openapi/v1/{paths,schemas,webhooks}/`
  when it grows. Every operation has an `operationId`, a summary, a
  description, its scope (`x-allure-scope`), its errors and an example.
- `webhooks:` documents every event type of §11.2 with its envelope schema;
  `components.securitySchemes.bearerAuth` is `http`/`bearer`.
- Served at `GET /api/rest/v1/openapi.json` and `GET /api/rest/v1/openapi.yaml`
  to a signed-in session or any valid token (no scope), with `servers` and
  `info.version` filled at request time and a strong `ETag`.
- **Validation in the suite** with the `openapi_first` gem (3.1 support):
  - every request spec under `spec/requests/api/rest/v1/` validates the
    request and the response against the document (a shared
    `api_contract` helper);
  - a guard spec asserts the routes under `api/rest/v1` and the document's
    `paths` are the same set, method by method;
  - a guard spec builds every webhook event's envelope from factories and
    validates it against its `webhooks` schema;
  - the document itself is linted (OpenAPI 3.1 meta-schema) in the suite.

## 13. The API reference page

### 13.1 Route and shell

`GET /developers/api`, members-only, rendered in the application layout with
the ordinary page header (« API » / "API"), an intro card (`DESIGN.md` §20.19)
and the reference below it, full width. `/developers` redirects to it. It is
linked from `/settings/api` and the footer; it is not a topbar item.

### 13.2 Scalar

`@scalar/api-reference`, pinned in `package.json`, bundled by Vite as its own
entrypoint (`entrypoints/api_reference.js`) and served as a bare document at
`GET /developers/api/reference` (layout `api_reference`, no application
stylesheet, `X-Frame-Options: SAMEORIGIN`), which `/developers/api` embeds in
a same-origin `iframe`. The isolation is required, not cosmetic: Tabler's
utility classes (`.grid`, `.p-3`, `.rounded`…) share names with Scalar's and
rewrite its layout when both live in one document. The frame's Stimulus
controller (`api_reference_frame_controller.js`) posts the theme to the
document on load and on every `allure:theme-changed`; the document carries
the brand colours and font stack itself (`styles/api_reference.css`).
Configuration:

- `url`: the same-origin `openapi.json`;
- no proxy (`proxyUrl` unset), `withDefaultFonts: false`, telemetry off, and
  every feature that calls a Scalar service (AI agent, registry, client
  download) disabled — the page makes no request outside the instance;
- `persistAuth: false`: a pasted token is never written to `localStorage`;
- dark mode driven by `data-bs-theme`, updated on `allure:theme-changed`, the
  toggle hidden; accent colours from the brand tokens through Scalar's CSS
  variables;
- "Try it" requests go to the page's own origin (`servers` is set from
  `window.location`, whatever host the document advertises) with the pasted
  token only; the page never pre-fills a token, and the session cookie it also
  sends is ignored by the API (§4.5).

The bundle is large (about 470 kB gzipped); it is a separate entrypoint and
loads only inside the frame.

### 13.3 Language

The page chrome (header, intro card, copy of `DESIGN.md` §19.26) is bilingual
like every page. The document's contents — summaries, descriptions, problem
`title`/`detail` — are **English only**: they are developer documentation and
protocol text, like the ActivityPub vocabulary, and duplicating them would
let the two languages drift on a contract. `DESIGN.md` §20.19 records the
exception.

## 14. Administration and metrics

- `/admin/accounts/:id` gains an « API » section: tokens (name, prefix,
  scopes, expiry, last use) with revoke, and webhook endpoints (host, events,
  state, failure count) with disable. Both audited.
- `/admin/jobs` shows the `webhooks` queue with the others.
- Metrics (`[devdoc:metrics]`, mapped in `Metrics::Catalog`, no label carries
  a host, account or token):
  - `allure_api_tokens{status}` (`active`, `expired`, `revoked`);
  - `allure_api_requests_total{scope, status_class}` (Yabeda counter);
  - `allure_webhook_endpoints{status}` (`active`, `inactive`, `disabled`);
  - `allure_webhook_deliveries{status}` over the last 24 h;
  - `allure_webhook_delivery_oldest_pending_seconds`.

## 15. Reserved for OAuth 2

A later contract will add `api_applications` and authorization grants; it
reuses the scope names of §4.3 verbatim and lets an `api_tokens` row carry an
application. Nothing in v1 anticipates it beyond the scope vocabulary and the
`Bearer` scheme.
