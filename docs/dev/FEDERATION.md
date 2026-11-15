# Federation contract

The ActivityPub transport: permanent identity, signatures, discovery, inbox and
outbox, delivery, remote identity and follows, remote notes and media, the
safety gate, and the restricted audience. The object-specific contracts live
elsewhere: `PUBLISHING.md` for a workout publication, `COMMENTS.md` for a
comment thread, `REACTIONS.md` for a reaction, and `SEGMENTS-FEDERATION.md` for
a course. This document covers how those objects travel.

## 1. Scope and vocabulary

- **Actor** — one ActivityPub identity. A local actor belongs to one account; a
  remote actor is a cached copy of another instance's identity.
- **Inbox / outbox** — the receiving and sending endpoints of an actor.
- **Delivery** — one physical POST of one outbox event to one inbox URL.
- **Entitlement** — the right of one local actor to read one received object.
- **Capability** — the operator's assessment of what a remote instance supports,
  never a remote self-claim.
- **Tombstone** — a durable `410 Gone` identity, kept after deletion.

## 2. Permanent identity

`Allure::Federation::Config` is the only source of permanent instance identity:

- base URL;
- scheme, host and port;
- actor, key, inbox, outbox, followers and following URIs;
- profile URL, handle and WebFinger account;
- local-URI checks;
- the private-IP escape hatch for the local test ring.

All federated IDs derive from this object. Never hardcode a hostname,
reconstruct an actor URI from a handle, drop a non-default port, or infer HTTPS.
Scheme, host and port together form permanent actor identity.

`FEDERATION_BASE_URL` defaults to `http://allure.test:3001` in development.
`FEDERATION_PROTOCOL` selects `http` or `https` and must match the base URL's
scheme. Plain HTTP is only for the local ring with `ALLOW_PRIVATE_IPS=true`;
production must use HTTPS.

### 2.1 `actors`

`actors` is the single identity table for local and remote actors.

| Column | Type | Meaning |
|---|---|---|
| `id` | bigint | primary key |
| `user_id` | bigint | nullable; unique for local actors |
| `local` | boolean | not null, default false |
| `uri` | text | not null, unique permanent actor URI |
| `handle` | string | nullable display/discovery handle, not an identity source |
| `acct` | string | nullable resolved `user@domain`, including a non-default port |
| `display_name` | string | nullable cached actor name |
| `summary` | text | nullable sanitized cached actor summary |
| `public_key_id` | text | nullable until a remote actor is fully fetched |
| `public_key_pem` | text | nullable only for a tombstoned actor with no usable key |
| `private_key_ciphertext` | text | nullable; local only and encrypted |
| `private_key_retired_at` | datetime | nullable key cleanup timestamp |
| `inbox_url` | text | nullable for tombstoned or incomplete remote actors |
| `shared_inbox_url` | text | nullable |
| `avatar_url` | text | nullable remote avatar source, never rendered directly |
| `avatar_cached_at` | datetime | nullable last successful avatar cache time |
| `capability_profile` | string | `unknown`, `public_only`, `restricted_fetch`, `restricted_shared_inbox` |
| `last_fetched_at` | datetime | nullable actor-cache timestamp |
| `tombstoned_at` | datetime | nullable deletion timestamp |
| `raw` | jsonb | nullable original normalized actor document |
| timestamps | datetime | Rails audit columns |

Rules:

- `local = true` requires an actor URI under the configured local base URL and
  either a current `user_id` or a tombstone waiting for terminal Delete
  deliveries or already marked `private_key_retired_at`.
- `local = false` requires no local user and must not contain a private key.
- A local actor with `user_id = NULL` must have `tombstoned_at` set and must not
  accept new follows, publications or profile updates.
- A tombstoned actor may have a null private key only when
  `private_key_retired_at` is set and no non-terminal signed Delete delivery
  remains.
- A local user has at most one actor row.
- `uri` is immutable after creation.
- `public_key_id` must be an absolute URI and is validated against the fetched
  actor document before use.
- A tombstoned actor remains addressable for `410` behavior; its row is not
  deleted as part of ordinary cleanup.
- Remote actor `raw` data is replaceable and is never trusted without schema and
  URI validation.
- `capability_profile` defaults to `unknown` and is assigned only by a tested
  software/version allowlist or an explicit local peer policy. A remote
  self-claim is not sufficient to authorize followers-only media.

`acct` is stored from the WebFinger subject when discovery provided one, and
from `preferredUsername@authority` otherwise. `authority` preserves the port:
`host` when the port is the scheme default, otherwise `host:port`. Metadata
refresh may update `acct`, `avatar_url`, key, inbox and raw document; it never
updates `capability_profile` outside the peer policy.

Indexes: unique `uri`; unique `user_id` where `local = true`;
`(local, last_fetched_at)`; `tombstoned_at`.

### 2.2 Keys and provisioning

`Federation::ActorProvisioner` provisions a stable local actor with an encrypted
RSA key. `public_key_id` names the key URI; `private_key_ciphertext` is encrypted
at rest. A local actor is provisioned before its first publication or follow.

`Federation::ActorKeyRetirement` destroys the private key only when every outbox
event and delivery for the actor is terminal. It runs from
`Federation::RecoveryJob` and is idempotent. `Signature::Signer` may sign with a
tombstoned local actor while its private key is present and
`private_key_retired_at` is blank: the withdrawal is created before tombstoning
and delivered after it.

### 2.3 Discovery

- **WebFinger** — `GET /.well-known/webfinger?resource=acct:user@domain` returns
  the actor link. A WebFinger `self` link vouches only for the authority it was
  discovered on: the actor URI's authority (host and non-default port) must
  match the queried handle's domain. A domain can never alias another
  instance's actor under its own handle.
- **Actor** — `GET /users/:username` returns the Person resource with the public
  key, inbox, outbox, followers and following collections. A tombstoned actor
  answers `410 Gone`.
- **NodeInfo** — `/.well-known/nodeinfo` and the NodeInfo document expose the
  software name/version and the instance metadata. They never expose account
  identities or counts.
- **Collections** — the followers and following collections stay empty on the
  wire. The outbox collection is bounded and paginated; it never materializes
  every event or payload.
- **Shared inbox** — `POST /inbox` accepts activities for several local actors.
  A peer that advertises a shared inbox receives one POST per shared inbox, not
  one per actor.

## 3. HTTP security

### 3.1 Outbound signatures

Every outbound POST and signed GET carries `Signature` with
`(request-target) host date digest`:

- `Digest` is `SHA-256=` over the exact body; a GET signs the SHA-256 of the
  empty body.
- `keyId` is the local actor's `public_key_id`.
- `Date` is within the receiver's clock skew.
- The signature is computed over the exact bytes sent, after serialization.

### 3.2 Inbound verification

`Federation::Signature::Verifier`:

- requires `Signature`, `Date` and `Digest` headers;
- verifies the body digest before parsing JSON;
- resolves the remote actor without persisting it, verifies the signature
  against its key, and saves the fetched or refreshed row only after the
  signature verifies;
- rejects an activity whose `id` is not on the actor's authority;
- rejects a stale or replayed `Date`;
- returns `401` for an invalid signature and `403` for a blocked authority.

A request whose signature never verifies leaves no actor row behind, so an
unauthenticated POST naming a fresh actor URI cannot fill `actors` with
document-sized rows.

### 3.3 SSRF guard

`Federation::Transport::Client`:

- accepts only `http`/`https`; plain HTTP only with `ALLOW_PRIVATE_IPS=true` for
  the local ring;
- resolves the host and refuses private, loopback, link-local and reserved
  addresses;
- revalidates every redirect hop and forbids an HTTPS downgrade;
- applies a total timeout across redirects and address resolution, and abandons
  an address resolution after 3 seconds;
- caps the response body at the caller's `max_bytes:` (1 MB for inbox and
  discovery traffic);
- never follows a redirect to another authority for media.

### 3.4 Actor cache

A cached actor fetched less than 5 minutes ago is not fetched again. An actor
whose fetch or verification failed is not fetched again for 5 minutes; the
request is answered `503` with `Retry-After`, so a peer that really rotated its
key gets through on a later retry. At most one request thread per process
fetches a signer at a time; another request needing a fetch is answered `503`
with `Retry-After`.

Signed GETs resolve the signer only when the instance already has its actor row
(`known_only`). An unknown signer is served exactly what an anonymous reader is,
without a fetch and without a row.

## 4. Activity contract

### 4.1 Workout Note

`Federation::Serializers::WorkoutNote` serializes a publication. The
representation itself is `PUBLISHING.md`; the wire adds the `tag[]` dialect.

| Tag name | Canonical key | Unit | Notes |
|---|---|---|---|
| `category` | `sport_label` | string | not a metric |
| `distance` | `distance` | metres | `m` suffix |
| `duration` | `duration` | seconds | `m` suffix but seconds |
| `moving_time` | `moving_time` | seconds | `m` suffix but seconds |
| `pause_time` | `pause_time` | seconds | `m` suffix but seconds |
| `elevation_gain` | `ascent` | metres | |
| `elevation_loss` | `descent` | metres | |
| `min_elevation` | `min_elevation` | metres | plain numeric |
| `max_elevation` | `max_elevation` | metres | plain numeric |
| `average_speed` | `average_speed` | m/s | plain numeric |
| `max_speed` | `max_speed` | m/s | plain numeric |
| `average_pace` | `average_pace` | seconds | plain numeric |
| `best_pace` | `best_pace` | seconds | plain numeric |
| `grade_adjusted_pace` | `grade_adjusted_pace` | seconds | plain numeric |
| `average_heart_rate` | `average_heart_rate` | bpm | plain numeric |
| `max_heart_rate` | `max_heart_rate` | bpm | plain numeric |
| `average_cadence` | `average_cadence` | rpm | plain numeric |
| `max_cadence` | `max_cadence` | rpm | plain numeric |
| `average_power` | `average_power` | W | plain numeric |
| `max_power` | `max_power` | W | plain numeric |
| `calories` | `calories` | kcal | plain numeric |
| `record_types` | `record_types` | string | comma-separated canonical record types |
| `record_distances` | `record_distances` | string | comma-separated best-effort distance keys |
| `device` | `device` | string | recording device or software, bounded to 120 characters |
| `commute` | `commute` | boolean | presence flag; `true`/`false`/`1`/`0` understood |
| `comments` | `comments_closed` | boolean | presence flag; `closed` stores `true` |

Rules:

- A tag is `{"type" => "Note", "name" => ..., "content" => ...}`.
- Metre-suffixed values accept a trailing `m` and must be finite and
  non-negative.
- Values outside a bounded range are recorded as warnings and skipped for that
  metric; they do not reject the object.
- Unknown tag names are preserved in `raw` and ignored.
- `Mention` and any non-`Note` tag type are preserved in `raw` and ignored.
- Duplicate metric tags keep the first value and record a warning.
- Record markers are dedicated tags with a comma-separated token list; tokens
  are allowlisted, unknown or oversized tokens are skipped, duplicates keep the
  first occurrence, and each tag is capped at 32 tokens and 512 characters.
- `device` is emitted only when the profile shares it; content is stripped and
  truncated to 120 characters.
- `commute` is emitted only when the profile shares it and the workout is a
  commute.
- `comments` is emitted only when the profile closed comments; the receiver
  stores `comments_closed: true` and refuses its composer.

### 4.2 Attachments

- At most four entries.
- `Image` with `mediaType: image/png` and a URL, optionally carrying
  `allure:theme: dark`. The route image may be advertised twice — the light
  image first, the dark one marked — so an older receiver keeps the first
  `Image` and a current receiver stores both.
- `Document` with `mediaType: application/xml+gpx` and a URL.
- Unknown types and extra entries are ignored and recorded in `raw`.
- URLs are absolute http(s) with no userinfo or fragment.
- A URL whose authority differs from the author's is skipped with a warning: the
  media fetch is signed with a local actor's key, so an attachment on another
  instance would let the sender read, as that local actor, media the sender is
  not entitled to.

### 4.3 Activities

| Activity | Meaning |
|---|---|
| `Create` | a new object (publication, comment, reaction) |
| `Delete` | withdrawal of an object or an actor |
| `Follow` | a follow request |
| `Accept` | acceptance of a follow |
| `Reject` | refusal of a follow, or of a comment the host does not accept |
| `Undo` | withdrawal of a follow, a reaction, or an `Announce` |
| `Like` | a reaction on a received note |
| `Announce` | the comments relay on a public publication |

`Update` is rejected with "Update is not supported; Delete then Create". An
unknown activity type is terminally rejected.

### 4.4 Audience and entitlement

- A public object includes `#Public` in `to` or `cc`; the author's followers
  collection may also appear in `cc`.
- A followers object includes the author's followers collection and never
  `#Public`.
- Any other audience is rejected.
- A public object admits one entitlement per local actor the activity reached
  **that accepts the sender as followed**: local accepted followers of the
  sender when the audience carries `#Public` or the sender's followers
  collection, and a directly addressed actor only when it too follows the
  sender. Naming a local account is not enough.
- A followers object is rejected for every principal while
  `FEDERATION_RESTRICTED_ENABLED` is off.
- Entitlement is a property of a local actor, not of the instance. Two local
  accounts that both follow the same remote author have two entitlement rows.

### 4.5 Tombstones and actor deletion

- A `Delete` marks the received note `deleted` and never hard-deletes its
  identity.
- A `Delete` for an object never seen locally creates a deleted tombstone row
  with the author, object URI, activity URI and `received_at`.
- A `Create` for a tombstoned object URI is terminally rejected; the tombstone
  always wins, so out-of-order delivery cannot resurrect removed content.
- Comments are the documented exception (`COMMENTS.md`): a `Delete` for a
  comment never seen is refused instead of tombstoned, because a comment row
  needs a thread a bare `Delete` never names.
- Republishing on the sender always produces a new object URI; the receiver
  treats it as a new note.

Local actor deletion is a signed withdrawal, not a bare row delete:

- `Federation::ActorDeletion` withdraws every active publication first, then
  creates one `Delete` event with `subject_type: Actor` while the actor is still
  current, and only then tombstones the actor.
- The payload object is the embedded tombstone:
  `{"type" => "Delete", "actor" => actor.uri, "object" => Tombstone}` with
  `Tombstone = {id, type, formerType: "Person", deleted}`.
- The Delete audience carries an explicit `recipients` list computed before
  tombstoning: accepted remote followers plus every actor with an attempted
  delivery for this actor. The whole list stays on the outbox row for
  expansion; on the wire each destination receives only the actors of its own
  authorities.
- `Users::DeleteAccount` destroys the user row only after the Delete intent is
  durable (`[devdoc:account]`).

## 5. Inbox, outbox and delivery

### 5.1 Inbox admission

`Federation::Inbox::Admission`:

- resolves the activity's expected recipients and requires the URL recipient to
  be among them for a personal inbox;
- for a shared inbox, keeps audience resolution and checks blocks before actor
  resolution;
- checks `Safety::Blocks` for the claimed actor URI and its authority before
  resolving the remote actor;
- checks `Safety::InboundRateLimiter` for the remote authority and returns a
  distinct `RateLimited` error;
- stores `remote_domain` on every admitted item;
- validates size limits before parsing;
- requires the activity `id` to live on the actor's authority;
- resolves the remote actor without persisting it, and saves it only after the
  signature verifies.

`InboxesController` maps `RateLimited` to `429` with `Retry-After` and `Blocked`
to `403`.

### 5.2 Inbox processing

`Federation::Inbox::Processor` runs inside the inbox item's transaction:

- `Create` with an embedded note goes to `Inbox::Create`; with `inReplyTo` it
  goes to `Inbox::CommentReceipt` (`COMMENTS.md`).
- `Delete` resolves the object URI, requires its authority to match the
  sender's, marks the note deleted, withdraws every entitlement and purges
  media. A comment URI is handled by the comment branch.
- `Reject` finds the matching `Following` by its remote URI, or hands the
  activity to `Inbox::CommentRefusal`.
- `Undo` withdraws a follow, a reaction, or an `Announce`.
- `Announce` goes to `Inbox::CommentRelay`; `Undo(Announce)` to
  `Inbox::CommentRelayUndo`.
- Unknown activity types and `Update` are terminally rejected.
- A rejected item is never retried; a processing error retries with bounded
  backoff.

### 5.3 Outbox events

`federation_outbox_events` records one local intent and a stable payload
snapshot:

| Column | Meaning |
|---|---|
| `actor_id` | not null local actor |
| `subject_type` | `WorkoutPublication`, `SegmentPublication` or `Actor` |
| `subject_id` | nullable local row ID; nullable after source deletion |
| `event_uuid` | not null unique event identity |
| `activity_type` | `Create`, `Delete`, `Undo`, `Follow`, `Accept`, `Like`, `Reject` or `Announce` |
| `activity_uri` | not null unique stable activity ID |
| `object_uri` | not null stable object URI |
| `payload` | not null serialized activity snapshot |
| `audience` | not null `to`, `cc` and related addressing |
| `status` | `pending`, `expanded`, `complete`, `cancelled`, `failed` |
| `attempts` | not null, default 0 |
| `last_error` | nullable |

Rules:

- The payload is generated only after the object passes publication and privacy
  checks. It contains no private notes, raw coordinates, raw media URLs or
  private keys.
- Outbox creation is part of the same transaction as the publication state
  transition.
- `activity_uri` is stable across retries and is derived from the object URI and
  `event_uuid` as `#{object_uri}/activities/#{event_uuid}`.
- Delivery ordering is per `(actor_id, object_uri)`. A `Delete` cannot be sent
  before its predecessor `Create` has reached a terminal delivery state for that
  target. A secondary publication event also waits for the publication's own
  `Create`, and its `Undo` for the `Announce` it undoes.
- Fan-out happens after commit. A failed fan-out cannot roll back the workout.
- Repeated state transitions must not create duplicate `Create` or `Delete`
  events for one publication.

### 5.4 Deliveries

`federation_deliveries` is one physical POST to one inbox URL:

| Column | Meaning |
|---|---|
| `outbox_event_id` | not null |
| `inbox_url` | not null resolved physical endpoint |
| `status` | `pending`, `delivering`, `reconciling`, `delivered`, `retrying`, `cancelled`, `failed` |
| `attempts` | not null, default 0 |
| `next_attempt_at` | nullable |
| `last_response_status` | nullable |
| `last_error` | nullable sanitized error |
| `gone_recovery_used` | not null, default false |
| `lease_until` | nullable worker lease expiry |
| `delivered_at` | nullable |

Rules:

- Unique `(outbox_event_id, inbox_url)` prevents duplicate physical fan-out.
- A delivery is never sent without resolving and validating its target inbox.
- A `410 Gone` response triggers one cache-bypassed actor re-resolution. If the
  actor remains gone or has no safe inbox, the delivery is cancelled. A second
  `410` recovery attempt is terminal.
- Temporary 4xx/5xx and network failures follow bounded exponential backoff;
  permanent validation failures become `failed` without infinite retries.
- Delivery is at-least-once: a worker crash after the POST and before the row is
  updated can cause a duplicate POST. Stable ActivityPub IDs and receiver-side
  idempotency are the correctness mechanism.
- A stale `lease_until` can be reclaimed by a later worker. Reclamation never
  resets the stable activity ID or creates a second delivery row.

`federation_delivery_recipients` retains logical audience members for a
physical delivery: `delivery_id`, `actor_uri`, `status` (`pending`,
`authorized`, `withdrawn`), unique `(delivery_id, actor_uri)`. Before a POST,
re-check that at least one recipient remains authorized for the event's
audience.

### 5.5 Recipient authorization

`Federation::Delivery::RecipientAuthorizer` is used from both expansion and
pre-POST delivery:

- `Create` requires a currently eligible relationship and destination.
- `Delete` must reach actors who may already possess the object, even if they
  later unfollow.
- A secondary publication event is delivered only to a recipient of the
  publication's own `Create` whose delivery holds or is about to hold the note,
  and who still passes the publication rules.
- A secondary `Delete` keeps the attempted set of its own `Create`; a secondary
  `Undo` goes to the attempted set of the activity it undoes.

### 5.6 Recovery

`Federation::Outbox::StatusReconciler` and `Federation::RecoveryJob` keep the
outbox and media work moving. Every operation is idempotent and bounded.
Recovery may enqueue duplicate jobs, but stable event and delivery identities
prevent duplicate logical activity rows.

## 6. Remote identity and follows

### 6.1 WebFinger account

`Federation::WebFingerResolver` passes the resolved `acct:user@domain` string to
`Federation::ActorResolver`. `ActorResolver` stores `acct` and derives `handle`
with the authority including a non-default port. A profile URL, badge or search
result uses `acct` when present and `handle` otherwise. `acct` is display and
discovery data; it never replaces the actor URI as the identity used for
signatures, inboxes or object URIs.

### 6.2 Peer capability policy

`ActorResolver` assigns `capability_profile` from `FederationPeerPolicy` by the
actor's authority on create and refresh; the default is `unknown`. The actor
document never supplies capability. The operator promotes a domain to
`restricted_fetch` or `restricted_shared_inbox` after the peer's behavior is
verified. Lowering or removing a policy sets affected actors back to `unknown`
and becomes effective at the next authorization check.

### 6.3 Follow lifecycle

| State | Meaning | Transitions |
|---|---|---|
| `pending` | relationship requested, not decided | accept, reject, undo |
| `accepted` | active relationship | undo |
| `rejected` | inbound request declined | none |
| `undone` | relationship withdrawn | a new follow creates a new row |

Outbound:

- `Federation::Follow` provisions the local actor, resolves the target, and
  creates a pending `Following` plus a stable outbox `Follow` event.
- A local target gets a pending request with no federation event; the target
  decides it on `/people`, and a new request after a rejection resets the same
  row to pending.
- A pending outbound follow shows a Retry action when resolution or delivery
  failed; retry reuses the stable event identity. Local requests have no event
  to retry, so they only offer cancellation.

Inbound and local decisions:

- Local relationships do not require `FEDERATION_ENABLED`: the demo seed can
  establish them with the wire protocol disabled. Remote targets are refused
  before resolution while the switch is off.
- The processor creates or reuses a pending `Following` and emits nothing.
- `Federation::FollowDecision` accepts (`accept!`, plus an `Accept` event for a
  remote follower) or rejects (`reject!`, plus a `Reject` event for a remote
  follower). A local follower's decision changes state only.
- `Federation::Unfollow` emits `Undo(Follow)`.
- No inbound follow is accepted automatically: `/people` lists incoming
  requests with Accept and Reject actions.

### 6.4 Avatar proxy and cache

`Actor#avatar_url` is read from the actor document's `icon` when it is a single
absolute http(s) URL. `Federation::FetchActorAvatarJob` fetches through the SSRF
guard with the image limit, verifies magic bytes and dimensions, and attaches
`avatar_cache`. Avatars are fetched on profile view, follow or search, at most
once per cache window. An application route keeps the browser talking only to
its own instance; a missing or failed cache falls through the avatar
component's normal fallback chain. No remote avatar URL is ever rendered in
HTML.

### 6.5 Search, profiles and routes

| Route | Purpose |
|---|---|
| `GET /people` | signed-in relationship hub: following, followers, incoming requests, outgoing pending, search (`[devdoc:people]`) |
| `GET /people/search` | name-search fragment over discoverable members and existing relationships |
| `POST /people/resolve` | resolve `@user@domain` or actor URI, cache the actor, redirect to the remote profile |
| `GET /@:handle` | remote profile when the handle contains `@`; local `/@:username` is unaffected |
| `GET /@:handle/avatar` | cached remote avatar, served by the application |
| `POST /federation_follow` | follow |
| `DELETE /federation_follow` | unfollow |
| `PATCH /people/follows/:id` | accept or reject an inbound request |
| `DELETE /people/followers/:id` | remove an accepted follower |
| `DELETE /people/suggestions/:id` | dismiss a suggestion permanently |
| `GET /following` | `302` redirect to `/feed` |

Remote profiles show the cached identity (avatar, display name, `acct` badge), a
sanitized bio, published remote notes admitted for the current local account,
and follow/unfollow state. A remote profile that is not cached resolves through
the authenticated search; a tombstoned actor returns `410` on its protocol
endpoint and a not-found human state.

## 7. Remote notes and media

### 7.1 `remote_notes`

| Column | Meaning |
|---|---|
| `actor_id` | not null remote author |
| `object_uri` | not null unique received object identity |
| `activity_uri` | not null Create activity identity |
| `status` | `active` or `deleted` |
| `audience` | `public` or `followers` |
| `title` | nullable sanitized title |
| `description` | nullable sanitized plain-text description |
| `content_html` | nullable sanitized HTML |
| `sport_label` | nullable remote sport category label |
| `started_at` | nullable remote start time |
| `published_at` | nullable object published time |
| `received_at` | not null local admission time |
| `deleted_at` | nullable |
| `source_domain` | not null authority derived from the actor URI |
| `metrics` | not null normalized numeric metrics |
| `representation` | not null normalized presentation snapshot |
| `route_metadata` | not null route shape metadata |
| `raw` | not null normalized raw object |
| `warnings` | not null parser warnings |
| `location_data_purged_at` | nullable cleanup marker |

Rules:

- `(status = 'deleted') = (deleted_at IS NOT NULL)`.
- `metrics`, `representation`, `route_metadata` and `raw` are JSON objects;
  `warnings` is a JSON array.
- `source_domain` is non-empty and never contains a scheme or path.
- `object_uri` and `activity_uri` are absolute http(s) URIs.
- A `deleted` row is a durable tombstone; it is never destroyed by ordinary
  cleanup.
- `representation` mirrors the local publication shape but is a separate
  remote-only value: `title`, `description`, `sport_label`, `started_at`,
  `metrics`, optional `record_types`, `record_distances`, `device`, `commute`,
  `comments_closed`, `location`, `track`, `chart`, and an explicit `redacted`
  marker after cleanup.

### 7.2 Entitlements

`remote_note_recipients`: `remote_note_id`, `recipient_actor_id`, `status`
(`active` / `withdrawn`), `withdrawn_at`, `withdrawal_reason`, `inbox_item_id`.
Unique `(remote_note_id, recipient_actor_id)`. Withdrawal reasons are
`unfollow`, `rejected`, `blocked`, `deleted`, `unreachable`; they are
diagnostics, never user-facing state. A recipient must be a local actor.

`RemoteNoteRecipient#withdraw!` is the single withdrawal path, called from
`Delete` processing, local unfollow, follow rejection, an actor or domain block,
and remote actor deletion. Withdrawal is idempotent. `RemoteMedia::Purge`
removes media and location-bearing representation only for deleted notes or
followers-only notes whose last active entitlement was withdrawn; a public note
keeps its cached media until deletion or cleanup.

### 7.3 Attachments

`remote_note_attachments` is the persisted descriptor, created before any fetch:
`remote_note_id`, `kind` (`gpx` / `route_image`), `theme` (`light` / `dark`),
`remote_url`, `media_type`, `status` (`pending`, `fetching`, `cached`, `failed`,
`unavailable`, `purged`), `attempts`, `next_attempt_at`, `last_error`, `blob_id`,
`content_digest`, `byte_size`, `fetched_at`, `purged_at`. Unique
`(remote_note_id, kind, theme)`.

`remote_url` is absolute http(s) with no userinfo or fragment, and its authority
must equal the note's `source_domain`. It is revalidated by the SSRF guard
immediately before every fetch, and `RemoteMedia::Fetch` re-checks the authority
so a descriptor can never point a locally signed GET at a third party. A
`purged` descriptor retains no `blob_id`, `content_digest` or `byte_size`.

### 7.4 Fetch and verification

`Federation::SignedFetcher` resolves the local actor used for signing (the first
active entitlement actor for the note), signs `(request-target) host date
digest` with an empty-body digest, passes the requested media type through
`Accept`, and calls `Transport::Client#get` with a caller-supplied `max_bytes:`.

| Limit | Value |
|---|---|
| Activity body | 1 MB |
| Attachments per note | 4 |
| Route image bytes | 5 MB |
| Route image pixels | 40 million |
| GPX bytes | 10 MB |
| GPX points | 50 000 |
| GPX segments | 500 |
| Media read timeout | 30 s |
| Fetch attempts | 5 with capped backoff |

Verification:

- Route image must start with the PNG signature and decode through Vips within
  the pixel cap. The stored `content_digest` is the SHA-256 of the exact bytes.
- GPX must parse with `Allure::Gpx::Parser` under the point and segment limits
  with Nokogiri `NONET`. External entities are never resolved. The remote parser
  runs with `require_timestamps: false`: Allure's sanitized publication GPX
  omits timestamps by contract.
- A declared but wrong media type is a verification failure, not a note failure.

### 7.5 Parsed geometry

A verified GPX is parsed into an `Allure::Gpx::Track` value. The remote track
GeoJSON follows the local publication rules: one `LineString` feature per source
segment, coordinates `[longitude, latitude]`, only a `segment_index` property.
`elapsed_time` is derived from `<time>` only when the source carries it; Allure's
sanitized GPX does not, so its chart points carry `distance` and `elevation`
with `elapsed_time` null. The remote chart is bounded by
`Allure::Gpx::ChartSeries` (1 000 points). `route_metadata` records bounds and
segment count only when a usable track exists. A remote note never creates a
`Workout`, `TrackSegment`, owner attachment or segment effort.

### 7.6 Serving

`GET /remote_notes/:id/media/gpx` and
`GET /remote_notes/:id/media/route-image` (and `?theme=dark`) go through
`Federation::RemoteNotePolicy` for every request. The attachment must be
`cached` and its blob must still exist; a missing or mismatched blob returns
404. Responses are `private, no-store` and always controller-mediated; raw
Active Storage URLs never appear. The route image is the card image and the
fallback detail image; the detail page uses the interactive map when a parsed
track exists. Media still being fetched renders a partial state inside a Turbo
Frame that refreshes itself until the descriptors settle. Page rendering never
performs a remote fetch.

### 7.7 Failure, retry and purge

`pending -> fetching -> cached` is the success path. `pending|fetching ->
failed` after bounded retries; the note still renders with a media-unavailable
state. `pending -> unavailable` for a blocked domain, an unsupported content
type or no active entitlement. `cached|failed -> purged` on note deletion,
last-entitlement withdrawal, author block or actor deletion. Purge removes the
blob, clears the descriptor's blob reference and digest, removes `track`,
`chart` and `location` from the representation, and sets
`location_data_purged_at`. Repeated purge is a no-op. The recovery sweep
re-enqueues `pending` and due `failed` work from database intent, never from
in-memory state.

## 8. Safety gate

### 8.1 Blocks

`Federation::Safety::Blocks` is consulted by inbox admission, outbox expansion
and pre-POST delivery authorization, remote media and avatar fetch, and remote
profile resolution. A blocked authority or actor URI receives `403` on
admission, is skipped during fan-out and fetch, has its notes' entitlements
withdrawn, and is counted in diagnostics.

An authority is a DNS name, so every authority and actor-URI block key folds the
host case. The path stays case-sensitive. A domain block without a port covers
that host, every subdomain and every port; a block with a port covers exactly
that authority. Peer policies keep exact matching: a promotion is never
inherited by a subdomain.

### 8.2 Rate limits

- Inbound: at most 60 admitted activities per minute and 600 per hour per remote
  authority, evaluated against `federation_inbox_items.remote_domain` and
  `created_at`. Exceeding the limit returns `429` with `Retry-After` and
  persists nothing.
- Inbound requests: at most 300 per minute per client address on the inbox
  endpoints, refused with `429` and `Retry-After: 60` before the body is read.
- Signer resolution: a cached actor fetched less than 5 minutes ago is not
  fetched again; every attempt that reaches a fetch counts against 30 per minute
  per authority and 60 per minute per site; an actor whose fetch or verification
  failed is not fetched again for 5 minutes; at most one request thread per
  process fetches a signer at a time.
- Outbound delivery: at most 5 concurrent deliveries per target authority.
- Remote fetch: at most 2 concurrent fetches per authority via the media job.

### 8.3 Input caps

| Limit | Value |
|---|---|
| Title | 255 characters |
| Description | 10 000 characters |
| Content HTML | 10 000 characters |
| Tag entries processed | 200 |
| Audience entries | 200 |
| Actor summary | 2 000 characters |
| Actor document | 256 KB |

Oversized or malformed individual values are dropped with a warning; a document
that violates the activity-level cap is rejected.

### 8.4 Sanitization

`Federation::RemoteText` is the single sanitizer. It uses the Rails HTML5
safe-list sanitizer with an allowlist of paragraphs, line breaks, emphasis,
strong, lists and links. Links receive `rel="nofollow noopener noreferrer"`.
Images, scripts, styles, iframes, forms and event attributes are removed.
Sanitization runs at parse time and at render time.

### 8.5 Operator diagnostics

`/admin/federation` is operator-only and shows inbox item counts by status,
delivery counts by terminal state and authority, media attachment counts by
status, blocked domains and actors, peer policies, and remote note counts by
status. `Federation::Diagnostics` builds those aggregates and never returns
coordinates, raw payloads, private keys, inbox bodies or remote HTML. The page
offers block/unblock, peer promotion/demotion and a media retry action. All
writes are operator-authorized and audited. No user-facing screen names the
protocol.

### 8.6 Social-graph confidentiality

The followers and following collections stay empty; admission must not reveal
the graph either.

- An `Accept` routes only through a follow the sender is the followed party of;
  an `Undo` only through a follow or a reaction the sender made. A URI naming a
  row the sender is not party to answers exactly like an unknown URI, whatever
  the row's status.
- A remote Follow's activity URI is random from the first attempt: a URI derived
  from the two actors could be computed and probed elsewhere. Idempotency rests
  on the active relationship, not on the URI.
- An event that names its recipients one by one keeps the whole list on the
  outbox row, but every payload that leaves carries only the listed actors of
  the destination's own authorities. `#Public` and the followers collection pass
  unchanged.

## 9. Restricted federation

`FEDERATION_RESTRICTED_ENABLED` defaults to false in every environment. The
built-in followers profile is always selectable and publishable; custom profiles
remain public-only. Its owner and accepted local followers read a followers
publication whatever the switches say. While false, nothing followers-only
leaves or enters the instance: `Delivery::RecipientAuthorizer` refuses every
followers-only event, a signed remote principal is refused by both publication
policies, and `Inbox::Create` rejects a followers note. Recipients are decided
at expansion: turning the switch on does not deliver followers publications
made while it was off.

`Workouts::PublicationPolicy` gains the restricted branch:

| Principal | Public publication | Followers publication |
|---|---|---|
| Anonymous browser or protocol | allow per the public rules | 404 |
| Owner | allow | owner surface only |
| Unrelated local account | allow | 404 |
| Accepted local follower | allow | allow while the relationship is active |
| Accepted remote follower, `restricted_fetch` or `restricted_shared_inbox` | allow | allow, signature required |
| Accepted remote follower, `unknown` or `public_only` | allow | 404 |
| Pending, rejected, undone, blocked, tombstoned | public behavior only | 404 |

The remote rows additionally require `FEDERATION_RESTRICTED_ENABLED`, an active
publication, and a signature-verified remote request from the current follower;
the local rows depend on neither switch.

Signed fetches:

- The sender delivers followers-only objects only to capability-promoted peers,
  using personal inboxes unless the peer is `restricted_shared_inbox`.
- The receiver fetches followers-only media with a signed GET from the entitled
  local actor.
- The sender reauthorizes the requesting actor on every object and media
  request; no entitlement is cached.
- Local browser viewers never use those signed endpoints: the owner and any
  signed-in account entitled to the publication fetch the sanitized route image
  and GPX through application endpoints that re-run the publication policy with
  a browser principal.

Revocation: unfollow, reject, block and author deletion withdraw the local
entitlement and stop new deliveries. A followers-only object or media request
from a withdrawn follower returns 404 immediately. When the last entitlement for
a note is withdrawn, cached media and location-bearing representation are
purged. Already-fetched remote copies cannot be recalled; the UI must never
claim otherwise.

## 10. Presentation and navigation

- A remote account is badged, not styled differently: the same avatar, name and
  card, plus an instance badge (`@user@instance`).
- Nothing in the UI names the protocol: "un compte sur une autre instance", not
  "an ActivityPub actor"; "publiée", not "202 Accepted".
- Remote pages reuse the local vocabulary and components. The remote note page
  shows provenance, media states and the received representation; it never shows
  the origin's leaderboard, efforts or athletes.
- The top navigation carries one feed destination; `/following` redirects to it.
- Every user-facing string lands in every locale file in the same patch.

## 11. Tests

### 11.1 Offline

- Identity: WebFinger, actor, NodeInfo, collections, shared inbox, tombstone.
- Signatures: outbound headers, inbound verification, digest, clock skew,
  replay, key rotation.
- SSRF: scheme, private addresses, redirects, downgrade, timeouts, byte caps.
- Admission: personal vs shared inbox, recipient resolution, blocks, rate
  limits, activity-id authority, actor persistence after verification.
- Serializer and parser: exact `tag[]`, attachments, audience, warning and
  rejection matrices.
- Inbox: `Create`, `Delete`, `Reject`, `Undo`, `Announce`, idempotency,
  tombstones, entitlement withdrawal.
- Outbox and delivery: stable identities, fan-out, recipient authorization,
  retries, `410` reconciliation, ordering, secondary events.
- Remote media: descriptors, fetch, verification, parsing, serving, purge,
  recovery.
- Safety: blocks, rate limits, caps, sanitization, diagnostics.
- Restricted: audience matrix, signed GETs, revocation.

### 11.2 Ring

`dip fed_test` runs two complete instances and proves discovery, signed
`Follow`/`Accept`, sanitized public `Create`, `Delete`, idempotent redelivery,
media rendering, withdrawal and actor deletion. `dip fed_restricted_test` proves
followers-only delivery to promoted peers, entitlement-gated page and signed
object/media GET, refusal for an unsigned or non-follower request, and unfollow
revocation with purge.

### 11.3 HTTPS gate

The first production HTTPS federation is a manual gate: a stable hostname, a
valid certificate, a reachable WebFinger and actor, and a signed follow between
two instances. The preflight and the gate are recorded in the operator
runbook.

## 12. Out of scope

- Federated efforts, leaderboards and cross-instance competition.
- Federation of routes and loops (courses only, `SEGMENTS-FEDERATION.md`).
- External-peer dialects beyond the strict Allure Note profile; Mastodon and
  other ActivityPub software remain a separate interoperability target.
- A second publication model for workouts, or any change to the workout
  `Note` / `tag[]` / `attachment[]` contract.
- Per-account blocking, remote search directories, and instance discovery
  beyond WebFinger and NodeInfo.
- Feed cards, notifications, likes or comments for courses.
