# Segments federation contract

Course-only federated segment distribution. A shared course leaves an instance
as an immutable `Note`; no effort, athlete, alias, leaderboard row or personal
record ever crosses the wire. `SEGMENTS.md` covers the local course contract;
this document covers the wire and the receiving side.

## 1. Decisions

1. **Course only.** What leaves an instance is the course: geometry, name,
   description, sport and course metrics. No effort, athlete, alias,
   leaderboard row, personal record or anonymous identity ever federates. The
   origin leaderboard stays local to the origin instance.
2. **A dedicated object path.** The federated object lives at
   `#{base_url}/api/v1/segment/{shortuuid}`. It travels as a `Note`, not a new
   ActivityStreams type, but it is self-describing: the object path alone
   distinguishes a course from a workout publication's `/api/v1/trail/` object.
3. **One visibility axis.** A single `visibility` governs both the course and
   its board: `private`, `followers_only` or `public`. The federated audience is
   snapshotted from it — `public` or `followers` — and there is no per-board
   override.

| Area | Decision | Consequence |
|---|---|---|
| Scope | Course-only distribution | No effort, athlete or leaderboard serialization, ever |
| Object type | `Note`; no new ActivityStreams type | Receivers reuse the Note validation conventions |
| Object path | `/api/v1/segment/{publication shortuuid}` | Path alone distinguishes a course from a workout; the shortuuid encodes the immutable `SegmentPublication` |
| Shareable kind | `kind: "segment"` only | Routes and loops stay private |
| Publishing | Explicit owner action, as with workouts | Widening `visibility` changes the local board but never auto-emits a `Create` |
| Audience source | `segment.visibility`: `public` → Public + followers cc; `followers_only` → followers only | No per-segment federation control and no publishing profile |
| Multi-sport course | `sport_id: NULL` omits the `category` and `sport_slug` tags; a single-sport course sends the label and the slug | The receiver uses the neutral all-sports fallback; a copy maps the slug and stays all-sports otherwise |
| Restricted audience | Delivering `followers_only` requires `FEDERATION_RESTRICTED_ENABLED` and a promoted peer; publishing it does not | Mirrors the restricted workout publication |
| Replacement | Any represented edit while published is offered as a replacement | New publication identity; old one withdrawn; no remote `Update` |
| Remote consumption | Copy as a private local segment only | No foreign match target |
| Copy provenance | `segments.remote_segment_id`, one copy per user per remote course | Local copies survive remote deletion and unfollow |
| Remote page visibility | Signed-in local accounts only | Anonymous never sees remote copies |
| Media | GPX required, route image optional, both cached and application-served | A course Note without a GPX attachment is rejected |
| Remote route image | Never re-rendered | The verified PNG is cached as-is |
| Remote metrics | Display only, never trusted for matching | The local copy recomputes geometry and distance from the verified GPX |
| Elevation | The federated GPX carries 2D geometry only | No chart; ascent/descent travel as display-only tags |
| Update | Permanently rejected | Delete followed by Create |

## 2. Wire contract

### 2.1 Object

```json
{
  "@context": "https://www.w3.org/ns/activitystreams",
  "id": "https://allure.example/api/v1/segment/8Qh2mD",
  "type": "Note",
  "attributedTo": "https://allure.example/users/marie",
  "name": "Col du Test",
  "content": "Le col par le versant nord",
  "url": "https://allure.example/segments/7Yb1kP",
  "published": "2026-09-12T09:30:00Z",
  "location": {
    "type": "Place",
    "name": "Segment start",
    "longitude": 6.865,
    "latitude": 45.923
  },
  "to": ["https://www.w3.org/ns/activitystreams#Public"],
  "cc": ["https://allure.example/users/marie/followers"],
  "tag": [
    { "type": "Note", "name": "category", "content": "Vélo" },
    { "type": "Note", "name": "sport_slug", "content": "cycling" },
    { "type": "Note", "name": "segment_kind", "content": "segment" },
    { "type": "Note", "name": "distance", "content": "2500.000000m" },
    { "type": "Note", "name": "elevation_gain", "content": "180.000000m" },
    { "type": "Note", "name": "elevation_loss", "content": "12.000000m" },
    { "type": "Note", "name": "match_tolerance", "content": "25.000000m" },
    { "type": "Note", "name": "average_grade", "content": "7.200000" }
  ],
  "attachment": [
    {
      "type": "Image",
      "mediaType": "image/png",
      "name": "Route image",
      "url": "https://allure.example/api/v1/segment/8Qh2mD/media/route-image"
    },
    {
      "type": "Document",
      "mediaType": "application/xml+gpx",
      "name": "GPX course",
      "url": "https://allure.example/api/v1/segment/8Qh2mD/media/gpx"
    }
  ]
}
```

`url` is informational; a receiver must never require it to resolve, because a
followers-only origin page needs a session the remote browser does not have.

An all-sports course (`sport_id: NULL`) omits both the `category` and
`sport_slug` tag and has no `sport_slug` in its representation. A single-sport
course carries all three.

### 2.2 Tags

- `category` carries the sport label when the segment has exactly one sport, as
  in workout Notes; it is omitted for an all-sports segment, which the receiver
  renders with the neutral all-sports fallback.
- `sport_slug` carries the stable sport slug (for example `cycling`) when the
  segment has exactly one sport, and is omitted for an all-sports segment. The
  receiver stores it in the representation so a later local copy can map it to
  a `Sport` deterministically; `category` stays the display label.
- `distance`, `elevation_gain` and `elevation_loss` reuse the existing wire
  names, metre suffix and bounds.
- The course extension adds three tags with fixed bounds: `segment_kind`
  (`segment` only), `match_tolerance` (metres, `m` suffix, 5–100) and
  `average_grade` (percent, no suffix, −100–100).
- Unknown tags are preserved raw and ignored, exactly as `RemoteNote` does.

### 2.3 Attachments

- The **GPX attachment is required**: `Document`, `application/xml+gpx`,
  `url` = `${object_uri}/media/gpx`. It carries 2D geometry only — no
  timestamps, no elevation, no sensor values — mirroring Allure's
  timestamp-less sanitized GPX. A course Note without it is rejected as an
  invalid object, never stored as metadata with pending geometry.
- The route image is optional and may be advertised twice: `Image`,
  `image/png`, `url` = `${object_uri}/media/route-image`, and the dark variant
  marked `allure:theme: dark` at `url` = `${object_uri}/media/route-image-dark`.
  A receiver that predates the property keeps the first (light) image; a
  current receiver stores both.
- Caps apply unchanged: at most 4 attachments, byte/point/segment limits
  enforced by `RemoteMedia::Verifier`.
- Both URLs must share the author's authority: a GPX on another authority is
  skipped, which rejects the course as having no GPX attachment; a foreign
  route image is skipped with a warning.

### 2.4 Audience

- `public`: `to: [Public]`, `cc: [followers]`.
- `followers_only`: `to: [followers]`, `cc: []`.
- Anything else is rejected. On receipt, a public object creates one
  entitlement per receiving local actor; a followers-only object creates
  entitlements only for local actors with an accepted following of the author.

### 2.5 Dereference and signed GET

- `GET /api/v1/segment/:id` with `Accept: application/activity+json` returns the
  Note. Public objects are readable by any requester; followers-only objects
  require a verified signed request from an actor permitted by
  `Segments::PublicationPolicy`, re-authorized on every request.
- `GET /api/v1/segment/:id/media/gpx`, `/media/route-image` and
  `/media/route-image-dark` follow the same authorization.
- A withdrawn object no longer serves content, matching the answer a deleted
  workout publication gives.

### 2.6 Withdrawal

- `Delete` carries an explicit `recipients` audience computed from the
  attempted `Create` deliveries, exactly like
  `Workouts::PublicationWithdrawal`: every logical recipient whose Create made
  any network attempt, never an unattempted pending delivery.
- A receiver tombstones the remote segment. A `Delete` for an object the
  instance never saw stores a tombstone that rejects a later `Create` for the
  same URI.

## 3. Data model

### 3.1 `segment_publications` (outbound)

| Column | Type | Constraints and meaning |
|---|---|---|
| `id` | bigint | primary key |
| `uuid` | uuid | not null, default `gen_random_uuid()`, unique, ShortUUID source |
| `actor_id` | bigint | not null, immutable, owner's retained local actor |
| `segment_id` | bigint | nullable, `ON DELETE SET NULL` |
| `object_uri` | string | not null, unique, `Allure::Federation.config.segment_uri(short_id)` |
| `audience` | string | not null, `public` or `followers`, snapshotted from `visibility` |
| `representation` | jsonb | not null, immutable snapshot |
| `route_metadata` | jsonb | not null, bounds and point count |
| `status` | string | not null, `active` or `deleted` |
| `published_at` | datetime | not null |
| `deleted_at` | datetime | nullable |
| `sanitized_gpx_blob_id` | bigint | nullable, content type `application/gpx+xml` |
| `sanitized_route_image_blob_id` | bigint | nullable, content type `image/png` |
| `sanitized_route_image_dark_blob_id` | bigint | nullable, content type `image/png`, the dark variant |
| timestamps | datetime | Rails timestamps |

`representation` allowlist: `name description sport_slug kind distance ascent
descent average_grade match_tolerance track location`. It carries no
`started_at`, no workout metrics hash, no chart and no effort data. `sport_slug`
is optional and absent for an all-sports course. `track` is a
`FeatureCollection` with **exactly one** `LineString` feature whose only
property is `segment_index: 0`; validation mirrors
`WorkoutPublication#validate_track` with a cardinality of one. `location` is
the start point, if the sanitized geometry has one.

Model rules mirror `WorkoutPublication`: `HasShortId`, `attr_readonly` on
immutable attributes, `object_uri_for(uuid)`, one active publication per
segment, terminal `active → deleted` transition, retained non-tombstoned actor
belonging to the segment owner, and sanitized blobs verified by id and content
type.

No `PublishingProfile` is attached. The segment's own `visibility` is the
audience policy; there is no per-publication override and no federated
visibility control. Local leaderboard eligibility has no federated effect and
is never serialized; the former `segment` profile setting is retired. A course
publication carries the course, never an effort or a board.

### 3.2 `remote_segments` (inbound)

| Column | Type | Constraints and meaning |
|---|---|---|
| `id` | bigint | primary key |
| `object_uri` | string | not null, unique |
| `activity_uri` | string | not null |
| `actor_id` | bigint | not null, remote author |
| `source_domain` | string | not null |
| `audience` | string | not null, `public` or `followers` |
| `name` | string | not null, 1–120 while active; empty only for a tombstone |
| `description` | text | nullable, ≤ 2000 |
| `content_html` | text | nullable, sanitized through `Federation::RemoteText` |
| `sport_label` | string | nullable, from the `category` tag; absent for an all-sports course |
| `kind` | string | not null, `segment` |
| `distance` | decimal(14,3) | nullable, display only |
| `ascent` | decimal(12,2) | nullable, display only |
| `descent` | decimal(12,2) | nullable, display only |
| `average_grade` | decimal(5,2) | nullable, display only |
| `representation` | jsonb | not null, immutable sanitized snapshot |
| `route_metadata` | jsonb | not null, bounds |
| `status` | string | not null, `active` or `deleted` |
| `published_at` | datetime | not null, from the wire `published` |
| `received_at` | datetime | not null |
| `deleted_at` | datetime | nullable |
| `location_data_purged_at` | datetime | nullable |
| `warnings` | jsonb | not null, default `[]` |
| timestamps | datetime | Rails timestamps |

`representation` allowlist: `name description sport_slug kind distance ascent
descent average_grade match_tolerance track location redacted`. `sport_slug` is
optional and absent for an all-sports course. `track` is the same
single-`LineString` `FeatureCollection`. `match_tolerance` is the course
matching tolerance in metres, snapshotted for a later copy. A `redacted`
representation excludes `track` and `location` and is mutually exclusive with
them. Validation mirrors `RemoteNote`: GeoJSON shape, coordinate ranges, finite
values and deletion state coherence. A Delete-before-Create tombstone carries
an empty `name` and a redacted representation; name presence is validated only
while the record is active.

### 3.3 `remote_segment_recipients`

Mirrors `remote_note_recipients`: `remote_segment_id`, `local_actor_id`,
`status` (`active` / `withdrawn`), `reason`, `withdrawn_at`, unique
`(remote_segment_id, local_actor_id)`. Withdrawal is the single revocation
path.

### 3.4 `remote_segment_attachments`

Mirrors the remote-note attachment descriptor: `remote_segment_id`, `kind`
(`gpx` / `route_image`), `theme` (`light` / `dark`, default `light`),
`remote_url`, `media_type`, `status` (`pending`, `fetching`, `cached`,
`failed`, `unavailable`, `purged`), `blob_id`, `attempts`, `last_error`,
`content_digest`, `byte_size`, `fetched_at`, `purged_at`, `next_attempt_at`,
timestamps. The unique descriptor key is `(remote_segment_id, kind, theme)`.

The fetch, verification, processing, purge, recovery and retry services are
shared with remote-note attachments instead of being duplicated, and the models
stay separate. The seam:

- every attachment exposes `owner` (its `RemoteNote` or `RemoteSegment`),
  `fetch_job_class` (its `federation_media` job), `filename_stem` and
  `source_domain` (delegated from the owner);
- every owner exposes `active?`, `deleted?`, `audience`, `source_domain`,
  `actor`, `attachments`, `recipients.active`,
  `attach_remote_media!(track:, chart:, route_metadata:, at:)` and
  `redact_location!(at:)`;
- `RemoteSegment#attach_remote_media!` persists only `track` and
  `route_metadata`; the course has no chart, so the `chart:` argument is
  ignored.

### 3.5 Changes to existing tables

| Table | Change | Meaning |
|---|---|---|
| `segments` | add `privacy_zone_acknowledged_at` datetime, nullable | corridor acknowledgment, invalidated on geometry or tolerance change |
| `federation_outbox_events` | add `segment_publication_id` bigint, nullable | required for `subject_type = "SegmentPublication"`; `subject_id` must equal it |
| `segments` | add `remote_segment_id` bigint, nullable, FK nullify | provenance of a local copy |
| `segments` | partial unique index `(remote_segment_id, user_id) WHERE remote_segment_id IS NOT NULL` | one copy per user per remote course |

`FederationOutboxEvent::SUBJECT_TYPES` becomes
`%w[WorkoutPublication SegmentPublication Actor]`. No `remote_notes`,
`federation_inbox_items`, `actors` or `federation_peer_policies` change is
needed.

## 4. Outbound lifecycle

### 4.1 Publish

`Segments::Publisher` requires the owner, `kind == "segment"`, an active
segment, `visibility != "private"`, a satisfied corridor acknowledgment, and no
active publication. It builds a `Segments::PublicationCandidate`:

- geometry from the canonical `segment.geom` (2D, `[longitude, latitude]`);
- metadata from the segment and its stored course metrics;
- sanitized GPX built geometry-only, mirroring the existing sanitized GPX
  builder;
- route image rendered asynchronously on the `route_images` worker with the
  existing MapLibre pipeline and raster/tile-less fallbacks, or a
  segment-specific job if the workout job cannot be generalized.

The `Create` intent stays `preparing` until the route image is attached, like
`Federation::Outbox::PublicationCreate`. The publish action is explicit in the
UI; it is offered only when the segment is shareable.

### 4.2 Audience and capability

- `visibility: "public"` → audience `public`.
- `visibility: "followers_only"` → audience `followers`, always publishable
  like the built-in followers profile; it leaves the instance only while
  `FEDERATION_RESTRICTED_ENABLED` is on.
- `RecipientAuthorizer` gains a segment-publication branch: Create requires an
  active publication, an accepted follow and, for followers-only, a promoted
  peer capability; Delete requires a retained publication identity and an
  attempted recipient. `policy_allowed?` delegates to
  `Segments::PublicationPolicy`.
- `Segments::PublicationPolicy` answers both principals: a browser principal
  uses the local course visibility, and an actor principal uses the entitlement
  and capability rules for signed GETs.

### 4.3 Replacement on edit

- While an active publication exists, making the course more restrictive than
  the publication audience (`public` → `followers_only`, or any change to
  `private`) is **blocked**: the owner must withdraw or replace the publication
  first. A publication must never outlive the visibility that justified it.
- Any other represented edit (name, description, sport, geometry-affecting
  tolerance, active flag, or an opening `followers_only` → `public`) marks the
  publication **stale** and surfaces a republish action. Nothing is emitted
  automatically, so no new content is ever distributed without an explicit
  owner action.
- Republishing runs `Segments::PublicationReplacement`: create the new
  publication and its `Create`, then withdraw the old identity with the
  attempted recipient set, in that order, mirroring
  `Workouts::PublicationReplacement`.
- Local efforts are already rebuilt by the existing segment update rules; the
  publication never stores effort data.

### 4.4 Withdrawal and account deletion

- `Segments::PublicationWithdrawal` mirrors the workout service: idempotent,
  locks the publication, finds or creates the `Delete` event with explicit
  recipients, cancels unattempted Create deliveries, and marks the publication
  deleted.
- Deleting a segment with an active publication withdraws it first. Deleting a
  source workout does not withdraw the publication: `segment_id` nullifies and
  the identity survives.
- `Federation::ActorDeletion` withdraws active segment publications before
  emitting the actor tombstone.

## 5. Inbound processing

### 5.1 Routing

`Federation::Inbox::Processor` distinguishes `Create` / `Delete` activities
whose embedded object URI has the `/api/v1/segment/` path and routes them to
the segment receipt path; everything else keeps the remote-note path. A
URI-only object and `Update` remain terminally rejected for both object types.
`Parsers::RemoteNote` also rejects an object URI under the segment path, so a
misrouted object is never silently stored as a note.

### 5.2 Parser

`Federation::Parsers::RemoteSegment` is strict and separate from
`Parsers::RemoteNote`:

- the embedded object must be a `Note`;
- actor, `attributedTo` and object authority must agree;
- the object URI path must be exactly `/api/v1/segment/{shortuuid}` with a
  valid canonical ShortUUID. A workout `/api/v1/trail/` object is never parsed
  as a segment, and the reciprocal guard lives in `Parsers::RemoteNote`;
- `name` is required and bounded; `published` is a required valid timestamp;
- audience must be Public or the author's followers collection;
- `location`, when present, must contain valid coordinates;
- the known course tags are parsed with bounds; a value outside its bound is
  dropped with a warning, never stored. `sport_slug` is optional and absent for
  an all-sports course; `category` carries the display label;
- `segment_kind` must be present and equal to `segment`; `match_tolerance` is
  snapshotted for a later local copy;
- a valid GPX attachment is required; the route image is optional; caps are
  reused (`MAX_TAGS`, `MAX_AUDIENCE`, `MAX_ATTACHMENTS`, `MAX_WARNINGS`);
- unknown tags and attachments are preserved raw and ignored.

Returned warnings never block persistence of an otherwise valid object.

### 5.3 Create

`Federation::Inbox::Create` gains the segment path:

- reject when the author is blocked or tombstoned, when a tombstone exists for
  the object URI, or when the object is malformed;
- duplicate `object_uri` is idempotent and returns the existing row; a
  tombstoned object always wins;
- persist one `RemoteSegment` and its entitlement rows: one per receiving local
  actor for a public object, only accepted-follower local actors for a
  followers-only object;
- persist attachment descriptors as `pending` and enqueue fetches after
  commit, as remote notes do.

### 5.4 Delete

`Federation::Inbox::Delete` handles both object deletion and author deletion:

- mark the remote segment deleted, withdraw every entitlement with reason
  `deleted`, redact the location-bearing representation, and purge media;
- a Delete for an unseen object stores a durable tombstone;
- local copies are **not** touched. A copy is a private local segment owned by
  its copier; remote withdrawal never deletes it.

### 5.5 Entitlement withdrawal

Unfollow, rejection, block and remote author deletion withdraw matching remote
segment entitlements through the same path as remote notes. Public course media
is retained; a followers-only course is purged when its last entitlement is
withdrawn. The remote segment page is no longer readable without an active
entitlement.

### 5.6 Recovery and retry

`RemoteMedia::Recovery` re-enqueues due remote-segment attachments;
`RemoteMedia::Retry` and the operator media-retry control reset terminal
failures. `Federation::Diagnostics` gains remote-segment counts by status and
pending/failed attachment counts.

## 6. Remote media

- GPX: fetched through the signed-capable transport and SSRF guard, verified
  with the existing byte/point/segment caps and
  `Allure::Gpx::Parser.new(require_timestamps: false)`, cached as a blob, and
  parsed offline into the remote representation `track` (single `LineString`).
  Distance and bounds are recomputed geodesically; remote course metrics stay
  display-only columns.
- Route image: the verified PNG is cached as the card image and never
  re-rendered with Chromium.
- Blobs are served only through the application's own `/remote_segments/:id`
  endpoints. No raw Active Storage URL is ever exposed.

## 7. Presentation and copy-as-local

### 7.1 Routes

```ruby
get "/remote_segments/:id",                   to: "remote_segments#show"
get "/remote_segments/:id/track",             to: "remote_segment_tracks#show"
get "/remote_segments/:id/media/gpx",         to: "remote_segment_media#gpx"
get "/remote_segments/:id/media/route-image", to: "remote_segment_media#route_image"
post "/remote_segments/:id/import",           to: "remote_segment_imports#create"
```

### 7.2 Policy and states

`Federation::RemoteSegmentPolicy` is the single visibility boundary: a public
segment is visible to any signed-in local account; a followers-only segment
requires an active entitlement; anonymous visitors never see remote copies; a
deleted segment renders a tombstone page for former recipients only. Track and
media endpoints apply the same policy. Media pending and unavailable states use
the Turbo Frame auto-refresh precedent from remote notes.

### 7.3 Remote page

The page renders provenance (the remote handle with the same badge and avatar
components as any remote account), name, description, sport with the neutral
fallback, course metrics, the map and the media states. It names no protocol
and shows no origin leaderboard, no effort and no athlete.

### 7.4 Copy as local segment

`Segments::RemoteImporter`:

- requires a cached, verified track; the action is disabled until media is
  cached;
- recomputes `geom`, `start_point`, `end_point`, `bounds`, `distance` and the
  64-value `Allure::Geometry::ShapeSignature` from the parsed geometry. Remote
  distance and elevation tags are never used for matching;
- resolves the sport: a wire `sport_slug` that matches a local `Sport` becomes
  the copy's `sport_id`; an absent slug (all-sports course) or an unknown one
  yields `sport_id: nil` (all sports) and records a local warning. A course
  never changes its sport semantics by being copied;
- creates a local `Segment`: `kind: "segment"`, owner = current user,
  `visibility: "private"`, `match_tolerance_meters` default 25,
  `source_workout_id: nil`, `remote_segment_id` set. `ascent`, `descent` and
  `average_grade` may be copied from the wire as display-only values;
- is idempotent and returns the existing copy for the same user and remote
  segment;
- the existing `after_create_commit` backfill then matches the copier's own
  workouts locally. No match ever runs against the remote row.

The copy is a normal local segment. Its owner may later share it under their
own actor; provenance stays a local column and is shown on the local detail
page.

### 7.5 Discovery

Entitled remote segments appear on the remote profile alongside remote notes.
The feed does not include segments in v1.

## 8. Safety and privacy

- Blocks, inbound rate limits, transport limits, content caps, sanitization and
  delivery/fetch concurrency are inherited unchanged.
- **No effort crosses the wire.** No segment representation contains an effort,
  an athlete, an alias, a leaderboard row, a personal best, a user ShortUUID, a
  profile path or a coarse date. A negative spec asserts this on the serialized
  payload and the received representation.
- An anonymous effort remains purely local by protocol: ActivityStreams has no
  anonymous authorship, and course-only distribution makes the question moot.
- The origin leaderboard stays on the origin instance. A remote viewer never
  sees another instance's athlete rows.
- Privacy zones are not subtracted from a shared corridor; the corridor
  preflight and its stored acknowledgment are the control. This is a deliberate
  difference from workout publications and must be stated in the UI copy.
- A local copy is private data owned by its copier and survives remote
  deletion, unfollow and blocks.

## 9. Tests

### 9.1 Tier 1 — offline

- Serializer: exact `tag[]` names, metre suffixes, bounds, audience mapping,
  attachment URLs, the absence of any effort/athlete/date key, and the omission
  of `category` and `sport_slug` for an all-sports course.
- Parser: wrong object path, missing GPX, wrong `segment_kind`, attribution and
  authority mismatches, out-of-bounds tags, unknown tags preserved as warnings,
  an absent `category` accepted as an all-sports course, audience rejection,
  caps.
- Models: every check constraint, immutability, terminal status transitions,
  blob content types, one active publication per segment, one copy per user.
- Services: publish candidate geometry, replacement order, withdrawal
  idempotency and recipient set, importer recomputation, sport mirroring
  (resolved slug, absent, unknown), and idempotency, policy matrix for browser
  and actor principals.
- Jobs: duplicate Create, Delete-before-Create tombstone, entitlement
  withdrawal on unfollow, reject, block and author deletion, purge semantics
  for public versus followers-only.
- Negative privacy: the serialized payload and `RemoteSegment#representation`
  contain no `segment_effort`, athlete, alias or exact start time.
- Local: visibility matrix, 404 discipline, corridor preflight, directory
  filters, and multi-sport course rendering (`Tous sports` label and per-sport
  board sections).

### 9.2 Tier 2 — ring

- `dip fed_test` gains a segment phase: A publishes a public course, B renders
  it, copies it, and matches a local workout; duplicate Create stays
  idempotent; an edit plus republish changes the identity and withdraws the old
  object; Delete leaves a tombstone; a blocked peer gets 403 without delivery.
- `dip fed_restricted_test` gains a followers-only course phase:
  entitlement-gated page and signed object/media GET, refusal for an unsigned
  or non-follower request, and unfollow revocation with purge.

### 9.3 Browser

Segment publish flow with the corridor acknowledgment, remote page media
states, copy action and resulting local match, an all-sports course rendering
its neutral label and per-sport board sections, map lifecycle and Turbo
teardown, light and dark themes, desktop and mobile widths, and Turbo
back/forward.

## 10. Out of scope

- Federated efforts and cross-instance leaderboards, which would need
  per-athlete consent, effort verification, anti-cheat and revocation that this
  course-only contract deliberately avoids.
- Federation of routes and loops.
- Elevation samples in the federated GPX, and a remote elevation chart.
- Segment cards in the feed, segment notifications, likes and comments.
- Remote segment search, instance directories and external-peer dialects.
- Wanderer trail mapping.
- A "keep in sync" mode for a local copy; copies are independent.
- Warning or withdrawing an already-published course when a new privacy zone
  intersects its corridor.
- Crediting the origin actor when a copy is re-shared.
