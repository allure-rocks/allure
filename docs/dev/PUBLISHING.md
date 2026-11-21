# Publishing contract

An imported workout is private. Publishing freezes a sanitized copy — a
publication — that local readers and ActivityPub peers can read. This document
is the contract for that copy: the source workout, the profile that decides
what it shares, the immutable snapshot, the audiences, and the reader and
federation boundaries. `DESIGN.md` governs the interface; `ACCESS.md` governs
who may read a browser surface.

## 1. Vocabulary

- **Source workout** — the complete, owner-editable recording. It is never
  served to a non-owner.
- **Publishing profile** — a reusable, user-owned recipe that decides what a
  publication may share.
- **Publication** — an immutable, sanitized representation of one source
  workout, frozen at publish time.
- **Audience** — who may read a publication: `followers` or `public`.
- **Snapshot** — the frozen profile settings, route metadata and representation
  stored on the publication.

## 2. The source workout

`Workout` remains the canonical source. It owns the original file, the complete
track and sensor values, every metric, the private notes, and the owner's
editing experience.

The source workout is never used directly for a non-owner page or an outbound
ActivityPub object. Every reader sees a publication, or nothing.

## 3. Publishing profiles

A `PublishingProfile` is a reusable publication recipe. The built-in profiles
are `public` and `followers`; a custom profile is public-only. There is no
`private` profile: a workout with no live publication is `unpublished`.

A profile controls the permitted representation:

| Setting | Meaning | Default |
|---|---|---|
| `title` | share the workout title | on |
| `description` | share the description and public notes | on |
| `metrics` | list of shared metric keys | all but heart rate |
| `route` | share the sanitized route and interactive map | on |
| `route_image` | share the sanitized route image on cards | on |
| `basemap` | load third-party tiles on the published map and route image | on |
| `gpx` | offer the sanitized GPX download | off |
| `records` | share the held record markers, without values | off |
| `device` | share the recording device or software name | off |
| `commute` | share the commute flag | off |
| `weather` | share the frozen weather summary | off |
| `comments` | let readers comment | on |
| `mask_start` | require the departure to be covered by a privacy zone | on |
| `mask_finish` | require the arrival to be covered by a privacy zone | on |
| `photos` | share the frozen photos | off |
| `photo_captions` | share photo captions | off |
| `photo_positions` | share a photo's distance along the route | off |

`metrics` is a list, not a switch. New profiles share no heart rate
(`average_heart_rate`, `max_heart_rate`) until their owner ticks it; existing
profiles keep their stored list. The other health, photo, weather, device and
GPX settings are off by default.

`segment` is a retired key: an old snapshot may still carry it, and it is
ignored. Segment leaderboards follow the reader and the shared route instead
([SEGMENTS.md](SEGMENTS.md)).

A profile also carries policies that are not part of the snapshot:

- `publish_delay_seconds` — an optional safety delay before a publication
  becomes visible or federated ([DELAYED-PUBLISHING.md](DELAYED-PUBLISHING.md)). `immediate` is
  the default; the owner may pick another preset for one publish.
- `auto_publish` — an opt-in, acknowledged policy that publishes each recent,
  non-bulk import through the ordinary publisher once its enrichments settle
  ([AUTO-PUBLISHING.md](AUTO-PUBLISHING.md)). One automatic profile per audience and account;
  commutes and chosen sports may be excluded.

Changing a profile affects future publications only. An existing publication
keeps its immutable snapshot and must be replaced to pick up new settings.

The public federation identity is account-level. A profile does not create a
new ActivityPub actor or a per-publication pseudonym. Actor URI and username
remain visible to ActivityPub peers.

## 4. The publication

`WorkoutPublication` is an immutable sanitized representation of one source
workout. It is the only non-owner representation used by local pages, local
media endpoints, and ActivityPub objects and media.

The user-facing lifecycle is:

```text
unpublished -> scheduled -> published -> deleted
                    \------------------> deleted
```

The stored statuses are `scheduled`, `active` and `deleted`; "published" is the
user-facing name of `active`. The absence of a live publication means
`unpublished`.

- **Scheduled** — the snapshot is frozen but nothing local or federated refers
  to it. It activates at `scheduled_for`, or through the owner's publish-now
  action. Cancelling it goes straight to `deleted` with no federation traffic,
  because no peer ever learned its object URI.
- **Active** — the publication is served locally and eligible for federation.
- **Deleted** — terminal. The row keeps its identity for withdrawal, audit and
  cleanup; its object and media endpoints answer 404 immediately. A deleted
  object URI is never reused.

Deleting a publication does not delete the source workout. Republishing creates
a new publication UUID, ShortUUID, object URI, sanitized media, and ActivityPub
`Create` activity.

A workout carries at most one live publication per audience. Two audiences
therefore mean two publications, each with its own frozen snapshot — typically
a richer followers version beside a reduced public one.

Edits to the source workout, profile changes, and privacy-zone changes do not
mutate an active publication. The owner deletes the current publication and
explicitly publishes again when a different representation is wanted.

The owner reads a publication as a reader through
`?as=publication&audience=`; without the audience, the narrowest active
publication is shown.

## 5. The sanitized representation

A publication is built from sanitized values only. No builder reads a raw
attachment as a fallback.

- **Privacy zones** filter interior points before the snapshot is made. Active
  zones always filter; a profile cannot disable them.
- **Endpoint masks** are profile-controlled. When `mask_start` or `mask_finish`
  is enabled, the corresponding source endpoint must be covered by an active
  privacy zone. When it is disabled, that endpoint may remain visible. A
  segment that never leaves a zone keeps no endpoint exemption, so the route
  fails closed instead of exposing it.
- **The route** is stored as sanitized metadata and geometry. A publication
  whose profile hides the route carries no route geometry, and its map and
  route image render without it.
- **The GPX** is a sanitized download, separate from the original file.
- **The route image** is a sanitized snapshot, rendered asynchronously on the
  route-image worker. The light and dark variants are generated together.
- **Photos** are immutable copies of the owner's stripped display files. A
  photo whose placement or EXIF position lies in an active privacy zone is left
  out by default; sharing it without position requires an explicit
  acknowledgement ([PHOTOS.md](PHOTOS.md)).
- **The representation** is frozen. Source, profile and zone changes never
  rewrite it.

Never in a publication: raw coordinates, private notes, original attachments,
integer database identifiers, or a secret. Health data, photos, weather,
device, commute and GPX are shared only when their setting says so. A metric
the sport cannot express is never frozen either: pace for a ride, speed for
a run (`Sport.metric_visible?`, the same channel rule as records) — whatever
the file recorded and the profile allows.

## 6. Audiences and readers

`WorkoutPublication::AUDIENCE_PRECEDENCE` lists the audiences from the
narrowest to the widest:

```text
followers, public
```

A future group audience goes before `followers`.

`Workouts::PublicationResolver.new(workout:, user:, audience: nil).call` is the
single answer to "which publication does this reader get": the narrowest active
publication whose `Workouts::PublicationPolicy` allows `:workout` for the
browser principal, restricted to `audience` when given. Nil means 404.

It drives the workout page, the track and chart endpoints,
`Workout#viewable_by?`, reactions, comments and `workout_display`.

- **Feed** — one item per workout. The candidate publications are deduplicated
  by workout, narrowest first, and the chosen publication is handed to the
  card.
- **Profile** — counts and sums use `served_to(current_user)`, so a follower
  never counts a workout twice.
- **Leaderboards** — an effort appears to a viewer through any active
  publication of the workout that viewer may read (`visible_to`) with its route
  shared, and ranks once ([SEGMENTS.md](SEGMENTS.md)).
- **Owner preview** — `?as=publication&audience=`; without it, the narrowest
  active publication.

`WorkoutPublication.served_to(user)` returns one publication per workout among
`visible_to(user)`, narrowest first. `visible_to(user)` returns every
publication the reader may read.

### Comments

One thread per audience. A reader reads the threads of every publication
serving them and writes to the narrowest. A reply takes its comment's audience
and needs the reader to be served a publication of that audience. The owner
picks the thread among the open active publications; the composer shows the
choice when more than one is open. A followers comment carries an « Abonnés »
badge when the reader sees several threads ([COMMENTS.md](COMMENTS.md)).

### Reactions

One count per workout, names per audience. A reaction records the audience it
was given through; every reader counts it, but only the readers of that
audience are named it ([REACTIONS.md](REACTIONS.md)).

### Browser access

Every browser surface is members-only (`ACCESS.md`). A visitor is redirected to
sign-in and returned to the requested page. The ActivityPub wire contract is
unchanged: remote peers have no Allure account.

### Resource and audience contract

Source-owner authorization and publication authorization remain separate.

| Resource | Anonymous | Owner | Unrelated member | Local accepted follower |
|---|---|---|---|---|
| `/workouts` library | redirect | source workouts | 404 | 404 |
| Public profile | redirect | active public snapshots, plus followers snapshots to entitled readers | active public snapshots | public and followers snapshots |
| Owner workout detail | redirect | complete source | snapshot only for an active public publication | snapshot only for an active public publication |
| Source track, chart, file, image | redirect | complete source | 404 | 404 |
| Publication track, chart, GPX, image | redirect | owner source surface remains separate | active public snapshot if enabled | active public snapshot if enabled, plus the followers snapshot when entitled |
| Followers-only publication | redirect | complete source through the owner surface | 404 | active followers snapshot |
| Deleted publication | redirect | 404 through publication endpoints | 404 | 404 |

The public profile is a publication surface even when viewed by the owner. It
never switches to complete source values based on session ownership.

On the protocol side, public objects and media remain publicly fetchable.
Followers-only objects and media require a verified signed request:

| Principal | Public publication | Followers publication |
|---|---|---|
| Unsigned request | allow | 404 |
| Signed unrelated actor | allow | 404 |
| Pending, rejected or undone follower | allow | 404 |
| Accepted remote follower with `unknown` or `public` capability | allow | 404 |
| Accepted remote follower with `restricted` capability | allow | allow while `FEDERATION_RESTRICTED_ENABLED` |
| Tombstoned actor | public anonymous behavior only | 404 |

An accepted relationship alone never exposes a followers-only object or media.

The outbox collection contract:

- `totalItems` and `orderedItems` use the same filtered relation;
- deleted publication `Create` activities are excluded;
- a `Delete` is visible according to its immutable recipient list, not the
  current follower status;
- `Follow`, `Accept`, `Undo` and `Like` events use their own exact activity
  audience;
- a public collection document never enumerates followers or following actor
  IDs;
- pagination is bounded and never materializes an unbounded collection.

## 7. Data model

### `publishing_profiles`

| Column | Meaning |
|---|---|
| `user_id` | owner; profiles are owner-scoped |
| `name` | user-facing name, 1–120 characters |
| `built_in_key` | `public` or `followers`, null for a custom profile |
| `audience` | `public` or `followers`; a custom profile is public-only |
| `settings` | allowlisted JSON object; never raw coordinates, zone centers, notes, keys or attachments |
| `position` | per-user display order |
| `publish_delay_seconds` | safety delay; one of the presets |
| `auto_publish` | automatic-publishing policy, off by default |
| `auto_publish_exclude_commute` | automatic-publishing exclusion |
| `auto_publish_excluded_sports` | catalog slugs excluded from automatic publishing |
| `uuid` | public identifier |

Constraints: unique `(user_id, built_in_key)` where the key is present; unique
`(user_id, audience)` where `auto_publish`; audience check; non-negative
position.

### `workout_publications`

| Column | Meaning |
|---|---|
| `uuid` | immutable publication UUID |
| `actor_id` | immutable local actor that owns the publication identity |
| `workout_id` | source workout; required while live, nullable only for a deleted publication after source deletion |
| `publishing_profile_id` | provenance; nullable after profile deletion |
| `status` | `scheduled`, `active` or `deleted` |
| `scheduled_for` | planned activation while scheduled |
| `published_at` | creation instant, or the actual activation instant |
| `deleted_at` | withdrawal instant |
| `object_uri` | immutable ActivityPub object URI |
| `profile_snapshot` | frozen profile settings and audience |
| `representation` | frozen sanitized representation |
| `route_metadata` | frozen sanitized route metadata |
| `privacy_zone_fingerprint` | fingerprint of the zones applied at publish time |
| `filtered_points_count` | number of points removed by zone filtering |
| `has_route` | whether the publication carries route geometry |
| `audience` | stored generated column, `profile_snapshot ->> 'audience'` |
| `location_data_purged_at` | cleanup marker after deletion |

Constraints:

- unique publication UUID and object URI;
- at most one live publication per `(workout_id, audience)`, enforced by the
  partial unique index `index_live_workout_publications_on_workout_and_audience`
  on `(workout_id, audience) WHERE status IN ('active', 'scheduled')`;
- `actor_id` and `published_at` are required;
- deleted rows retain their external identity;
- publication and media URLs use the publication ShortUUID, never an integer
  database ID;
- deleted publication object and media endpoints return 404 immediately;
- retained private blobs become purge candidates after admitted delivery work
  is terminal.

## 8. Federation boundary

Publishing is local first and federation-aware by design:

- a valid publication is available on the local instance;
- a public publication is eligible for ActivityPub distribution;
- a followers publication is eligible only for compatible restricted-audience
  peers, behind `FEDERATION_RESTRICTED_ENABLED`;
- a public publication is addressed to ActivityStreams `Public`, but it is not
  broadcast to every Allure instance or every fediverse server;
- delivery goes to known eligible recipients, and a remote server may fetch a
  public object when it knows its URI;
- no user-facing setting chooses between local publication and federation.

If no remote recipient is currently eligible, the publication remains active
locally. The absence or failure of a delivery does not make the local
publication disappear.

Each publication federates on its own: its own `Create`, its own `Delete`, its
own secondary events. `Federation::Delivery::RecipientAuthorizer` adds one rule
to a publication's own `Create`: a recipient the policy also serves through a
narrower active publication of the same workout is denied ("recipient is served
a narrower publication"). With a followers and a public publication, a promoted
follower receives the followers Note only; an unknown or public-only peer
receives the public one.

The rule is evaluated at expansion time and is not retroactive:

- a Note already delivered stays — a promoted peer that received the public
  Note before a followers publication existed holds both;
- withdrawing the followers publication does not send the public Note to the
  peers it was withheld from;
- promoting a peer later does not resend anything.

Receivers need no change: every Note is an ordinary Allure Note. The publishing
flow does not emit an `Update` for a local workout publication. Republishing is
a `Delete` followed by a new `Create` with a new identity.

## 9. Interface

The « Publications » card lists the scheduled then the active publications,
narrowest first. Each row carries its own Remplacer, Retirer, « Voir comme vos
lecteurs » and distribution alert. « Publier », « Ajouter une publication » and
« Remplacer » open a dedicated owner-only page. The form offers profiles for
free audiences and, when replacing, the named publication's audience. When
there is no free audience, the card explains why there is no add action.
The header « Retirer toutes les publications » withdraws them
all. Owner lists show one audience badge per active publication.

The form never projects the workout: the shared / not-shared sentence is laid
out as a list pair driven by the per-profile readiness data and shown before
submission. The owner reads
the published page itself through `?as=publication&audience=`.

## 10. Invariants and verification

The contract holds when:

- a newly imported workout is unpublished;
- the owner has one publishing flow, not separate local and federation
  visibility controls;
- public and followers profiles produce immutable sanitized publications;
- the same publication powers local non-owner views and the ActivityPub
  serializer;
- deleting a publication immediately removes its local representation;
- republishing creates a new external identity;
- no raw representation is reachable through a publication endpoint;
- federation consumes publications without reading the raw workout or
  implementing a second privacy policy;
- a reader is served one publication per workout, the narrowest they may read;
- one live publication exists per audience.

Specs cover profile ownership, built-in defaults, audience validation, one live
publication per audience, immutable snapshots and identities, unpublished
owner-only access, published authorization, deleted 404 behavior, deletion
preserving the source, republishing creating a new UUID, ShortUUID, URI and
`Create` intent, source/profile/zone changes not mutating an active
publication, imports always producing unpublished workouts, privacy filtering,
sanitized media, fail-closed output, the absence of raw coordinates, notes,
attachments and integer IDs, and the absence of a broadcast. `dip fed_test` and
`dip fed_restricted_test` keep the federation contract honest.
