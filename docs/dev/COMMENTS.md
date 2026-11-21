# Comments contract

Comments and one level of replies on a published workout, locally and across
Allure instances. Mentions are not part of this contract. This document defines
the product decisions, the durable rows, the authorization, the ActivityPub
wire contract, the inbound and outbound processing, the notification kind and
the surfaces. `DESIGN.md` governs the visual component; where the two conflict
on a data or protocol contract, this document wins.

`REACTIONS.md` is the closest precedent and its patterns are reused
deliberately: one write seam, a target that is the workout or the received note
rather than a publication identity, batched counts per page, a Turbo Frame
surface, and a notification kind with its switch.

## 1. Product decisions

| Subject | Decision |
|---|---|
| Authority | **The instance of origin hosts the thread.** A comment is sent to the publication's author; the origin validates it, stores it, and relays every accepted comment to every instance that received the publication. The model is the one Lemmy uses for communities: the thread host is the single authority on what the thread contains. |
| Target | A comment targets the **workout** on the origin and the **received note** on a reader's instance, never a publication identity — exactly like `Reaction`. Republishing keeps the local thread. A workout published to several audiences keeps one thread per audience (`comments.audience`, `PUBLISHING.md`). |
| Structure | **One level of replies.** A comment answers the publication or a top-level comment; a reply to a reply never exists locally. A reply received from the network whose parent is itself a reply is attached to that parent's root with a recorded warning, never rejected. |
| Editing | **None.** An author deletes and posts again. This matches the Allure change model: `Update` stays terminally rejected. |
| Owner controls | (1) The owner removes any comment on their workout. (2) The owner **closes and reopens** the thread at any time: `workouts.comments_closed_at`, live state, never in a snapshot. (3) A publishing profile setting `comments` (on by default) is frozen in the snapshot and **advertised on the wire**, so a reader's instance does not offer a composer the origin would refuse. Effective rule: *comments are open iff the snapshot's profile setting is on and the thread is not closed live*. A profile that disabled comments requires republishing to open them. |
| Who may comment | A signed-in account that may view the publication, **owner included** (the one difference from `:react`). On a reader's instance, a signed-in member who may view the received note (public, or held through an active entitlement). An anonymous visitor is redirected to sign-in (`ACCESS.md`). |
| Content | Plain text, 1 to 2 000 characters, line breaks preserved. No markup, no attachments, no mentions, no reactions on comments (`REACTIONS.md` keeps that exclusion). |
| Deletion | The author deletes their own comment (`Delete`, federated). The thread host removes any comment (`Reject` to the author, `Undo(Announce)` to everyone else). Both are durable states, never row deletion. |

Two limits are deliberate and documented rather than incidental:

- **Followers-only threads are never relayed.** On a publication delivered to
  the restricted audience (`FEDERATION_RESTRICTED_ENABLED`), a remote reader
  sees the owner's comments and their own; the thread is complete only on the
  origin. §6.6 explains why the relay is public-only.
- **A republished publication starts with an empty thread on remote
  instances.** The origin keeps the thread on the workout but does not replay
  it to the holders of the new note. A late comment that still names the
  withdrawn object is refused with a `Reject`.

## 2. Scope

### 2.1 Included

- `Comment` rows for local and remote authors on local workouts and on
  received notes, with one level of replies.
- Browser surfaces: the comments card on the workout page and on the received
  note page, a count pill on feed cards, the owner's close/reopen switch, the
  profile setting, the notification switch.
- The `:comment` resource on `Workouts::PublicationPolicy` and
  `Federation::RemoteNotePolicy`.
- Outbound `Create`, `Delete`, `Reject`, `Announce` and `Undo(Announce)`;
  inbound processing of the same; the comment object endpoint
  `GET /api/v1/comment/:id`.
- The transport extension for *secondary publication events* (§9), shared
  with the deferred `Invite` of [`SHARED-ACTIVITIES.md`](SHARED-ACTIVITIES.md).
- The `comment` notification kind.
- Ring coverage in `dip fed_test` and `dip fed_restricted_test`.

### 2.2 Excluded

Mentions, comments on courses (`SegmentPublication` / `RemoteSegment`),
reactions on comments, comment editing, rich text, attachments, thread
backfill after republishing, operator moderation of individual comments in
`/admin` (blocks and publication takedown remain the operator tools), comment
metrics in [METRICS.md](METRICS.md) (the catalog guard requires an `/admin`
counterpart that does not exist), email or push, and interoperability of
replies with non-Allure peers beyond what the strict contract happens to
accept.

## 3. Data model

### 3.1 `comments`

| Column | Type | Constraints and meaning |
|---|---|---|
| `id` | bigint | primary key |
| `uuid` | uuid | not null, unique, default `gen_random_uuid()`; the ShortUUID public identifier of a local comment |
| `actor_id` | bigint | not null, FK `actors`; the author, local or remote |
| `workout_id` | bigint | nullable, FK `workouts` cascade; thread hosted here |
| `remote_note_id` | bigint | nullable, FK `remote_notes` cascade; thread hosted on the origin |
| `parent_id` | bigint | nullable, FK `comments` nullify; the resolved top-level parent |
| `in_reply_to_uri` | text | not null; the wire parent: the publication's `object_uri` or the parent comment's `uri`, kept even when the parent is unknown locally |
| `uri` | text | not null, unique; `Allure::Federation.config.comment_uri(short_id)` for a local author, the remote object `id` otherwise |
| `activity_uri` | text | nullable, indexed; the `Create` that carried the comment (ours when local, the sender's when remote); correlates `Reject` |
| `audience` | string | not null, `public` or `followers`, inherited from the thread at creation |
| `status` | string | not null, default `active`: `active`, `deleted` (by the author), `removed` (by the host, a block, or the author's account deletion — see `removal_reason`), `rejected` (the origin refused a local author's comment on a received note) |
| `removal_reason` | string | nullable: `owner`, `blocked`, `actor_deleted`, `closed`, `not_allowed`, `inactive`, `full`, `unknown` |
| `body` | text | not null; the plain text (local author) or the sanitized text projection (remote author) |
| `content_html` | text | nullable; the remote author's sanitized HTML (`Federation::RemoteText.sanitize`); nil for a local author |
| `published_at` | datetime | not null |
| `deleted_at`, `removed_at`, `rejected_at` | datetime | nullable state instants |
| `confirmed_at` | datetime | nullable: the thread host's `Announce` of this instance's own comment came back, or a relayed copy was verified; recorded, never displayed (§11.2) |
| `relayed_by_actor_id` | bigint | nullable, FK `actors`: the host whose `Announce` delivered a third party's comment |
| `relay_activity_uri` | text | nullable, indexed: the `Announce` identity, so `Undo(Announce)` resolves |
| `source_domain` | string | nullable; the remote author's authority |
| `raw` | jsonb | not null, default `{}`; the embedded object as received, bounded to 64 KB |
| `warnings` | jsonb | not null, default `[]`; parser warnings |
| timestamps | datetime | Rails audit columns |

Constraints and indexes:

- check `comments_single_target`: exactly one of `workout_id`,
  `remote_note_id` (the `reactions_single_target` expression);
- check `comments_status` on the four statuses, `comments_audience` on the two
  audiences, `comments_removal_reason` on the listed reasons;
- check `comments_body_length`: `char_length(body) BETWEEN 1 AND 2000`;
- checks `comments_deleted_state`, `comments_removed_state`,
  `comments_rejected_state`: each non-active status carries its own instant
  and nothing else does; `comments_removal_reason_state`: a reason exactly
  for `removed` and `rejected`; `comments_json_shapes` on `raw` and
  `warnings`;
- unique `uri`, unique `uuid`, index `activity_uri`, index `in_reply_to_uri`,
  index `parent_id`, index `actor_id`, composite `(workout_id, created_at)` and
  `(remote_note_id, created_at)`, index `relay_activity_uri`.

Model `Comment`: includes `HasShortId`, so `to_param` is the ShortUUID and
both the local routes and the object endpoint resolve through
`find_by_short_id!` (a remote author's comment also has a `uuid`, which only
ever serves local routes and anchors);
`belongs_to :actor`, `:workout` (optional), `:remote_note`
(optional), `:parent` (optional, `class_name: "Comment"`),
`has_many :replies`; `attr_readonly` on `uuid`, `actor_id`, `workout_id`,
`remote_note_id`, `uri`, `in_reply_to_uri`, `audience`, `raw`; validations
mirroring the checks, a `parent_is_a_root_on_the_same_thread` validation
(depth one, same target), and the `reply_depth` invariant that a reply never
carries replies. Scopes: `active`, `roots`, `replies`, `for_target(target)`.
Helpers: `target` (workout or remote note), `local?` (author actor local),
`reply?`, `root`, `visible_in_thread?` (active, or a non-active root that
still has active replies), state transitions `mark_deleted!`,
`remove!(reason:)`, `reject!(reason:)`, `confirm!(activity_uri:)`, each
idempotent under a row lock.

`Actor has_many :comments, dependent: :restrict_with_exception` (an actor row
is tombstoned, never destroyed); `Workout has_many :comments, dependent:
:destroy`; `RemoteNote has_many :comments, dependent: :destroy`.

### 3.2 Other schema changes

| Change | Meaning |
|---|---|
| `workouts.comments_closed_at` datetime, nullable | the owner's live close/reopen switch |
| `users.notify_comments` boolean, not null, default true; `notifications_kind` check gains `comment` | the per-account notification switch |
| `PublishingProfile::SETTING_KEYS` and `BOOLEAN_SETTING_KEYS` gain `comments`; `DEFAULT_SETTINGS["comments"] = true` | profile settings live in the `settings` jsonb, no column. `comments` is the one key of `ABSENT_MEANS_ENABLED_KEYS`: a profile saved before the setting has no key and keeps comments open, so only an explicit `false` closes them — `PublishingProfile.setting_enabled?` reads it for the form, and the profile form stores an unchecked box as `false` instead of `nil` |
| `Allure::Federation::Privacy::SanitizedPublicationBuilder::REPRESENTATION_KEYS` gains the `comments` setting, which projects `comments_closed: true` when the setting is `false`; `WorkoutPublication#validate_representation` and `RemoteNote::REPRESENTATION_KEYS` accept `comments_closed` as a presence-only `true`, like `commute` | the profile setting on the wire |
| `FederationOutboxEvent::ACTIVITY_TYPES` and the `outbox_activity_type` check gain `Announce` | the relay |

No counter cache. Counts are computed per page by `Comments::Counts` (§5.5).

### 3.3 Invariants

- A comment's `audience` equals its thread's audience when it was created and
  never changes; it is what the object endpoint (§6.5) serves by.
- `in_reply_to_uri` is the single wire truth; `parent_id` is a local
  resolution that may be filled later (§7.2 steps 3 and 6).
- A non-active comment keeps its row and its `uri`: a late `Delete`, an
  `Announce` to undo, and "tombstone wins" need the identity, never the
  words. An author's deletion, or the author's account deletion, takes them:
  `body` becomes empty, `content_html` and `raw` go (migration
  `LetWithdrawnCommentsDropTheirText` lets only an active comment require a
  body), the `Create` this instance sent is redacted
  (`Federation::Outbox::PayloadRedactor`), and
  `FederationOutboxEvent.without_withdrawn_comments` keeps the `Create` of
  any withdrawn comment out of the actor's outbox collection. A comment the
  owner removed or the origin refused keeps its words for its author, who
  still sees it; a block only takes comments out.
- Comments are never part of a publication snapshot, a sanitized
  representation, a remote representation, or a route image: they are live
  social state read at render time.

## 4. Authorization

### 4.1 Local threads — `Workouts::PublicationPolicy`

`RESOURCES` gains `:comment`. `resource_allowed?(:comment)` requires the
publication to be active and `comments_open?` to hold; the audience gates are
those of `:workout`:

| Principal | Public publication | Followers publication (flag on) |
|---|---|---|
| `browser_user` owner | allowed | allowed |
| `browser_user` member | allowed | accepted local follower |
| `remote_actor` (inbound comment) | allowed | accepted and promoted follower |
| `protocol_anonymous`, `local_actor` non-owner, `anonymous` | refused | refused |

`comments_open?` is a `WorkoutPublication` method: the snapshot
`representation["comments_closed"]` is not `true`, and
`workout.comments_closed_at` is nil. The owner is allowed, which `:react`
refuses: a thread is a conversation, and the owner answering is the point.

### 4.2 Received threads — `Federation::RemoteNotePolicy`

`RESOURCES` gains `:comment`: the note is active, the principal is not
anonymous, the note is public or held through an active entitlement, and the
representation does not carry `comments_closed`. A `browser_user` resolves
through `user.actor`, exactly as for `:react`.

### 4.3 Denial

Denial in the browser is 404, never 403, like every other unauthorized
representation. On the protocol side a *policy* refusal (closed thread,
profile off, inactive publication, audience not met, full thread) is answered
with a `Reject` (§6.3) and the inbox item is rejected terminally; a
*malformed* object is rejected terminally with no answer; a blocked author
never reaches processing (403 at admission).

### 4.4 Caps

| Bound | Value | Where |
|---|---|---|
| Body | 2 000 characters of text | local validation, parser, database check |
| Remote HTML before sanitization | 10 000 bytes | `Parsers::RemoteComment::MAX_CONTENT_BYTES` |
| Retained raw object | 64 KB | `Parsers::RemoteComment::MAX_RAW_BYTES`, larger objects are rejected terminally |
| Active comments per thread | 1 000 | `Comments::Post` and `Inbox::CommentReceipt`; beyond it a local post is refused and a remote one gets `Reject` with reason `full`. On a received thread `Inbox::CommentReceipt` and `Inbox::CommentRelay` refuse a comment beyond it terminally, without an answer: the host bounds its own thread, this bounds a hostile one |
| Local posts per account | 20 per minute | `rate_limit` on `WorkoutCommentsController#create`, the sessions and passwords convention; a refusal is a 429 re-rendering the card with the text kept |
| Inbound body and rate | existing 1 MB cap and `Safety::InboundRateLimiter` | unchanged |

## 5. Behaviour

### 5.1 `Comments::Post` — the single local write seam

`Comments::Post.new(user:, target:, body:, parent: nil).call!` returns the
comment or raises `NotAllowed`, `Invalid` (blank, too long, parent not a root
of this thread, thread full), `Closed`.

1. authorize the target: a `Workout` through `Workouts::PublicationPolicy`
   with `PublicationPrincipal.browser(user)` and `:comment`; a `RemoteNote`
   through `Federation::RemoteNotePolicy` with `:comment`;
2. normalize the body (line endings become `\n`, C0 controls other than tab
   and newline and DEL are removed, three or more newlines collapse to two,
   every kind of leading and trailing space is trimmed) and validate the
   parent;
3. resolve the wire parent: the parent comment's `uri`, else the **currently
   active** publication's `object_uri` (local thread) or the note's
   `object_uri` (received thread);
4. in one transaction: create the row (`uri` from the new `uuid`, `audience`
   from the thread, `published_at` now), create the outbound intent (§8 —
   a `Create` to the thread host for a received thread, a `Create` to the
   publication audience for the owner's comment on a local thread; a
   non-owner local member's comment on a public local thread gets the host's
   `Announce` instead (§6.6, §8.4) and one on a followers thread no intent),
   store the `Create`'s `activity_uri` on the row (an `Announce` is found by
   its deterministic identity), and create the notifications (§10);
5. after commit, enqueue `Federation::ExpandOutboxEventJob` for each pending
   event. A queue failure never rolls the comment back; the recovery sweep
   owns pending events (the `Reactions::Toggle#enqueue_expansions!` rule).

### 5.2 `Comments::Delete` — the author

`Comments::Delete.new(user:, comment:).call!` requires `comment.actor ==
user.actor` and an active comment. It marks the row `deleted`, withdraws the
notifications it caused, and creates the `Delete` intent addressed where the
`Create` went (§8.1, §8.2). A local member's comment on a local thread has no
`Create` and needs no `Delete`; on a thread hosted here the deletion undoes
the relay (`Outbox::CommentUnannounce`, §8.4) so third parties drop it.

### 5.3 `Comments::Remove` — the thread host

`Comments::Remove.new(user:, comment:).call!` requires the workout owner and
an active comment on a local thread, and marks it `removed` with reason
`owner`. For a remote author it creates a `Reject` to that author with reason
`removed`, and `Undo(Announce)` goes wherever the relay went (§8.4) — the
author's instance included, where the two converge on the same `removed` /
`owner` state whichever arrives first. Notifications are withdrawn.

A single `DELETE /comments/:id` serves both: the controller dispatches to
`Delete` when the current account is the author and to `Remove` when it owns
the thread; an owner deleting their own comment is a deletion.

### 5.4 `Comments::Close` — the live switch

`Comments::Close.new(user:, workout:, closed:).call!` sets or clears
`comments_closed_at` for the owner. Closing does not touch existing comments
and federates nothing: a remote comment that arrives afterwards is refused
with `Reject` reason `closed`, which is the only way a reader's instance
learns it. Reopening is a plain clear. A workout whose active snapshot has
`comments_closed` cannot be reopened live; the page says so (§11.1).

### 5.5 Reading

- `Comments::Listing.new(target:, viewer:).call` (named after
  `Segments::Listing`; a `Comments::Thread` would shadow `::Thread` inside the
  namespace) returns the ordered thread:
  roots by `created_at` ascending, each with its replies ascending, authors
  and avatar caches preloaded in two queries. Visible: `active` comments; a
  non-active root that still has active replies renders as a stub (§11.1);
  the viewer's own `rejected` and `removed` comments on a received thread
  render for the viewer only, with their state. Everything else is hidden.
- `Comments::Counts.new(targets:).call` returns `{ target => count }` of
  active comments with one grouped query per target class, exactly as
  `Reactions::Summaries`, and the controllers set `@comment_targets` so a
  feed page never runs a query per card (`FeedsController`,
  `RemoteProfilesController`, `WorkoutsController#show`,
  `RemoteNotesController#show`).

## 6. Wire contract (strict Allure-to-Allure)

### 6.1 Identity

- `Allure::Federation::Config#comment_uri(short_id)` =
  `"#{base_url}/api/v1/comment/#{short_id}"`. The path segment follows the
  disambiguation rule already recorded for Wanderer-shaped objects:
  `/trail/`, `/segment/`, `/comment/`, plus `inReplyTo` presence.
- A local comment's `uri` is assigned at creation from its `uuid` through
  `ShortId`, the `WorkoutPublication#assign_publication_identity` pattern.
- Activity identities come from `Federation::Outbox::EventBuilder` with a
  per-comment idempotency key, so a retry never mints a second activity and a
  later `Delete`, `Reject`, or `Undo` references the same one:

| Activity | `subject_type` | `object_uri` | idempotency key |
|---|---|---|---|
| reader's `Create` to the host | `Actor` | `comment.uri` | `comment:create:<comment.uri>` |
| reader's `Delete` | `Actor` | `comment.uri` | `comment:delete:<comment.uri>` |
| owner's `Create` to the audience | `WorkoutPublication` (+ `workout_publication_id`) | `comment.uri` | `comment:create:<comment.uri>` |
| owner's `Delete` | `WorkoutPublication` | `comment.uri` | `comment:delete:<comment.uri>` |
| host's `Reject` | `Actor` | host actor `uri` | `comment:reject:<comment.uri>` |
| host's `Announce` | `WorkoutPublication` | host actor `uri` | `comment:announce:<comment.uri>` |
| host's `Undo(Announce)` | `WorkoutPublication` | host actor `uri` | `comment:undo-announce:<comment.uri>` |

`EventBuilder.activity_uri_for` mints `"#{object_uri}/activities/<uuid>"`, so
an activity about a *foreign* object (`Reject`, `Announce`, `Undo`) must use
the local actor URI as `object_uri`, the existing `Follow`/`Undo`/`Like`
pattern; an activity about a *local* comment uses the comment URI, the
publication pattern, which is what lets `Deliver#wait_for_predecessor?` order
a comment `Delete` after its `Create` with no change. An `Actor`-subject
event carries the signing actor's id as `subject_id` (the `ReactionLike`
shape); a `WorkoutPublication`-subject event carries the publication's id as
both `subject_id` and `workout_publication_id`, which the
`outbox_publication_subject_integrity` check requires.

### 6.2 The comment object

`Federation::Serializers::CommentNote.new(comment:).call` for a local author:

```json
{
  "@context": "https://www.w3.org/ns/activitystreams",
  "id": "https://allure-a.test:3002/api/v1/comment/7Kd2…",
  "type": "Note",
  "attributedTo": "https://allure-a.test:3002/users/marie",
  "inReplyTo": "https://allure-b.test:3003/api/v1/trail/Qx9…",
  "context": "https://allure-b.test:3003/api/v1/trail/Qx9…",
  "content": "Belle sortie !<br>On y retourne quand ?",
  "published": "2026-10-05T09:12:44Z",
  "to": ["https://allure-b.test:3003/users/paul"],
  "cc": []
}
```

- `content` is `ERB::Util.html_escape(body)` with newlines turned into
  `<br>`, the `WorkoutNote#content` rule. No `name`, no `tag`, no
  `attachment`, no `url` (the human page is members-only and useless to a
  peer), no `summary`.
- `inReplyTo` is the publication `object_uri` for a top-level comment and the
  parent comment's `uri` for a reply.
- `context` is the thread's object — the publication or received note a
  top-level comment answers, the one its root answers for a reply
  (`Comment#thread_object_uri`) — so a reader that never saw the parent still
  places the reply on its thread (§7.2, §7.5). It is optional on the way in
  and only a hint: an invalid value is a parser warning.
- **The audience of a comment is derived on the host, never carried on the
  wire.** A reader's comment is addressed to the host actor only — never
  `#Public`, never the sender's followers — so admission resolves exactly one
  recipient and no third party is ever addressed directly by the author. The
  owner's own comment carries the publication's audience (`to: [#Public]`,
  `cc: [owner/followers]`, or `to: [owner/followers]`), because the owner is
  the actor the recipients already follow.
- A remote author's comment relayed by the host is embedded **as received**
  (`comments.raw`), never re-serialized, so a receiver's refetch compares
  against the author's canonical object.

### 6.3 Activities

| Activity | From → to | Payload |
|---|---|---|
| `Create` | reader B → host A, `to: [A]` | `{type, actor, object: <CommentNote>, to, cc, id}` |
| `Create` | owner A → publication audience | same, with the publication's `to`/`cc` |
| `Delete` | author → wherever its `Create` went (`audience["recipients"]` = the attempted set, the `PublicationWithdrawal` rule) | `{type, actor, object: {type: Tombstone, id: <comment uri>, formerType: Note, deleted}, to, id}` |
| `Reject` | host A → author, `to: [author]` | `{type, actor, object: <comment Create activity URI>, _allure_reason, id}` |
| `Announce` | host A → publication audience (public only) | `{type, actor, object: <embedded comment object>, to: [#Public], cc: [A/followers], id}` |
| `Undo(Announce)` | host A → wherever its `Announce` was attempted (`audience["recipients"]`) | `{type, actor, object: {type: Announce, id: <announce uri>, object: <comment uri>}, to: <that set>, cc: [], id}` |

`_allure_reason` is a private property like `_allure_reaction`: `closed`,
`not_allowed`, `inactive`, `full`, `removed`. An absent or unknown value is
`unknown` and renders as the generic "not accepted" copy, never a rejection
of the `Reject`.

`Reject` reuses the activity type already introduced for follows; its meaning
extends to "the thread host did not accept, or no longer accepts, this
comment". Its object is the comment's `Create` activity URI, the follow
precedent, which the author's instance stored on the row at post time.

### 6.4 The profile setting on the wire

A snapshot whose profile disabled comments carries `"comments_closed" =>
true` in the sanitized representation (presence-only, the `commute` rule:
absent means open). `Federation::Serializers::WorkoutNote` emits
`{"type":"Note","name":"comments","content":"closed"}` in `tag[]` only in
that case; `Federation::Parsers::RemoteNote` parses the tag into
`comments_closed` on the received representation (any other content is a
warning and means open); `Federation::RemoteNoteView#comments_closed?` reads
it; `RemoteNotePolicy :comment` refuses on it. An older Allure peer ignores
the tag and simply has no comment feature; an older *receiver* of a closed
note never sends comments either.

### 6.5 The comment object endpoint

`GET /api/v1/comment/:id` (`Federation::CommentsController#show`, a
`ProtocolController`) finds a local-author comment by ShortUUID and serves
`CommentNote` as `application/activity+json`:

- `active` and `audience: public` → 200 to anyone, signed or not;
- `audience: followers` → 404 to everyone. Nobody needs to fetch such a
  comment: the host already holds it and followers-only threads are never
  relayed (§6.6). Refusing unconditionally is simpler and safer than teaching
  the author's instance a third party's entitlement on the host's note;
- `deleted` or `removed` → 404 (the object-level rule of
  `Federation::WorkoutsController`: no 410 for objects, only for actors);
- `Cache-Control: private, no-store`.

The endpoint exists for the relay verification and for any peer that resolves
a reply by its `id`.

### 6.6 Relay

Every accepted comment on a **public** local thread whose author is not the
owner — a remote reader's comment received by `Create`, or a local member's
comment posted on the owner's workout — is relayed by the host as an
`Announce` to the publication's attempted recipients. The owner's own comments
are not announced: they already travel as the owner's `Create`. The author's
instance is among those recipients — it holds the note it commented on — and
learns that the host took the comment. The announced object is the comment as
its author wrote it: a remote reader's exactly as received (§6.2), a local
member's as `CommentNote` serializes it, still addressed to the host alone.

Why public only: a receiver must verify an announced comment by fetching it
from its author (§7.5) because the host could otherwise forge a comment
attributed to any actor on the host's own workout. The author's instance can
serve a public comment to anyone, but cannot evaluate whether a third
instance is entitled to the host's followers-only note. Rather than trust the
host for that audience, Allure does not relay it.

A receiver's own comment coming back inside the host's `Announce` sets
`confirmed_at` (§7.5): the author's instance now knows the thread host
accepted it. The instant is recorded, not displayed (§11.2).

## 7. Inbound processing

### 7.1 Admission — no change

Every comment activity is addressed the way `Federation::Inbox::Admission`
already resolves: a reader's `Create`, the `Reject`, and the reader's
`Delete` name one local actor in `to` (`directly_addressed`); the owner's
`Create`, the `Delete` of an owner comment, the `Announce`, and
`Undo(Announce)` carry `#Public` or the sender's followers collection
(`follower_audience`). `recipients_for`'s `Undo` branch falls through to the
audience path when neither a `Following` nor a `Reaction` matches, which is
the `Undo(Announce)` case. The personal-inbox check holds for the same
reason. No `inReplyTo` branch is added to admission: a comment addressed to a
local actor who is not the thread host is admitted for that actor and then
rejected terminally by the handler, which is cheaper than a second lookup on
every `Create`.

### 7.2 `Create` with `inReplyTo` → `Federation::Inbox::CommentReceipt`

`Federation::Inbox::Processor#process_object(:create)` dispatches to
`Inbox::CommentReceipt` when the embedded object is a Hash carrying a
non-blank `inReplyTo`; otherwise `Inbox::Create` runs unchanged. (The
handler is not named `Inbox::Comment`: inside `Federation::Inbox` that name
would shadow the `::Comment` model.) The handler, in the inbox item's
transaction:

1. **Sender.** `@activity["actor"]` equals the item's `actor_uri`; the author
   is a cached, non-tombstoned remote actor; not blocked.
2. **Parse.** `Federation::Parsers::RemoteComment.new(activity).call` raises
   `InvalidObject` (terminal, no answer) unless: the object is embedded,
   `type == "Note"`, `id` is an absolute http(s) URI with no userinfo, query,
   or fragment whose authority equals the actor's, `attributedTo` equals the
   actor, `inReplyTo` is an absolute http(s) URI, `content` is a non-blank
   string within `MAX_CONTENT_BYTES`, and the raw object is within
   `MAX_RAW_BYTES`. It sanitizes `content` through `RemoteText.sanitize`,
   projects `RemoteText.text` into `body`, and rejects a projection longer
   than 2 000 characters. `name` is **not** required, which is the one
   difference from `Parsers::RemoteNote`. `published` is parsed with the
   existing `T`-required rule (absent → the receipt instant, warning).
   `tag`, `attachment`, and unknown keys are preserved in `raw` and ignored;
   a `Mention` is kept for a later annex.
3. **Idempotency first.** `Comment.find_by(uri:)` runs before anything else
   (step 5), so a redelivery is never refused by a thread closed meanwhile.
   Then resolve `inReplyTo`, in this order:
   - `WorkoutPublication.find_by(object_uri:)` → a local thread; the
     publication must be active and still belong to its workout (inactive,
     or replaced by a newer publication → `Reject` reason `inactive`, sent by
     the publication's actor);
   - `Comment.find_by(uri:)` → a reply; the parent must be active; its
     thread is the parent's; a parent that is itself a reply is flattened to
     the parent's root with warning `reply depth flattened`;
   - `RemoteNote.active.find_by(object_uri:)` → a received thread. The
     sender must be the note's author (the owner's comment; a third party's
     comment only ever arrives inside the host's `Announce`, §7.5); any other
     sender is rejected terminally. The item's recipient actor must be
     entitled to the note or the note must be public; otherwise terminal
     rejection (this local account never received the note). The
     received-thread bound of §4.4 applies;
   - nothing, but the object's `context` names a received note → the host
     answers a comment this instance never received (a relay still on its
     way, or refused here): the reply is stored as a root of that note with
     warning `parent comment not yet received`, keeping its
     `in_reply_to_uri`, until `Comments::Relink` attaches it (step 6);
   - nothing → terminal rejection `unknown thread`.
4. **Authorize.** Local thread: `Workouts::PublicationPolicy` with
   `PublicationPrincipal.protocol(author)` and `:comment`; a policy refusal
   creates the `Reject` intent (reason `closed`, `not_allowed`, or
   `inactive`) and rejects the item terminally. A full thread (§4.4) answers
   reason `full`. Received thread: nothing beyond step 3; the owner may
   always comment on their own publication.
5. **Idempotency.** `Comment.find_by(uri:)`: an existing row with another
   author is terminal (`object author does not match`); an existing
   `deleted` or `removed` row is terminal (tombstone wins); an existing
   `active` row returns it (a second recipient's inbox item for the same
   owner comment, or a redelivery). A race on the unique `uri` reloads the
   winner, the `Inbox::Create#find_or_create_record` rule.
6. **Create** the row: `actor`, target, `parent`, `in_reply_to_uri`, `uri`,
   `activity_uri: item.activity_uri`, `audience` from the thread,
   `body`, `content_html`, `published_at`, `source_domain`, `raw`,
   `warnings`. Then `Comments::Relink`: with the relay a reader can hold a
   reply before the comment it answers, so every root of the same thread
   whose `in_reply_to_uri` is the new comment's `uri` becomes its reply —
   under its root when the new comment is itself a reply, one level deep —
   unless that orphan already carries replies of its own. §7.5 runs the same
   step.
7. **Notify** (§10).
8. **Relay**: on a public local thread, build the `Announce` intent
   (`Outbox::CommentAnnounce`, §8.4) and push it on
   `processor.outbox_events` so `Federation::ProcessInboxItemJob` expands it
   after commit.

Comments hold no entitlement rows of their own: on a received thread the
note's `remote_note_recipients` already scope who may read, and the comment
row is one per `uri` whatever the number of local recipients.

### 7.3 `Delete`

`Federation::Inbox::Delete` resolves the object URI exactly as today (the
sender's authority must own it). Before the path routing it looks the URI up
in `comments`: a match is a comment deletion whatever the path — the author
must be the sender, `mark_deleted!`, notifications withdrawn, and on a thread
hosted here `Undo(Announce)` wherever the relay went (§8.4), pushed on
`processor.outbox_events`; already non-active is a no-op. An unknown URI
under `/api/v1/comment/` is rejected terminally; other unknown URIs keep the
note-tombstone behaviour.

This is a deliberate deviation from the rule that a `Delete` for an object
never seen creates a tombstone: a comment tombstone needs a thread and a bare
`Delete` names none, so a targetless row is impossible under
`comments_single_target`. The risk is bounded because every Allure sender
orders a comment `Delete` after its `Create` through
`Deliver#wait_for_predecessor?`; a `Delete` whose `Create` never arrived
describes a comment that never existed here.

### 7.4 `Reject`

`Processor#process_reject` keeps its follow branch and, when no `Following`
matches the object URI, hands the activity to `Inbox::CommentRefusal`, which
resolves `Comment.find_by(activity_uri: object_uri)`.
The comment must be a local author's comment on a received note whose author
is the sender (the thread host); then `reject!(reason:)` with
`_allure_reason` mapped onto `removal_reason` (`removed` → status `removed`
with reason `owner`; the others → status `rejected`), notifications
withdrawn (none exist for the author's own comment; the parent author's one
is withdrawn). Unknown comment, wrong sender, or an already non-active row is
a terminal rejection or a no-op respectively.

### 7.5 `Announce` and `Undo(Announce)`

`Processor` gains `when "Announce" then process_comment_relay` →
`Federation::Inbox::CommentRelay`, and `process_undo` gains `when
"Announce"` → `Federation::Inbox::CommentRelayUndo` (named like
`CommentReceipt` and `CommentRefusal` rather than `Inbox::Relay`).

`Inbox::CommentRelay`, in the inbox item's transaction:

1. the sender is the activity's actor, a cached, non-tombstoned, non-blocked
   remote actor;
2. the object is an embedded Hash parsed by `Parsers::RemoteComment` in
   *relay mode* — the object's `attributedTo` stands for the actor — so
   `attributedTo` must share its authority with the object `id` (the
   author's authority), **not** with the announcing actor;
3. idempotency first: `Comment.find_by(uri:)` on another thread than the
   sender's note is terminal; a withdrawn row is returned unchanged (a
   withdrawn comment never comes back); this instance's own author's comment
   → `confirm!(activity_uri:)`, no fetch; a relayed row → returned (a
   redelivery);
4. the thread: `inReplyTo` names a known comment (flattened to its root,
   which must be active) or a received note; a reply to a comment this
   instance never saw falls back to the note its `context` names and waits as
   a root (§7.2 step 3). The note must be active, authored by the sender —
   only the host relays its own thread — and **public**: a followers thread is
   never relayed (§6.6), so its `Announce` is refused even when the recipient
   holds the note. The received-thread bound of §4.4 applies;
5. the author: a blocked author drops the relay terminally, and a local URI
   with no local row is a forgery, refused; otherwise
   `Federation::ActorResolver#resolve(attributed_to)` (persisted; an invalid
   actor is terminal, a fetch error retries);
6. **verify** through `Federation::CommentFetcher`: a GET of the object `id`
   signed by the item's recipient actor (`Federation::SignedFetcher`), with
   `Accept: application/activity+json`, the 64 KB cap, a 10 s read and 15 s
   total timeout, through `Transport::Client` and its SSRF guard; the fetched
   object is parsed with the same parser and must match the embedded one on
   `id`, `attributedTo`, `inReplyTo`, and the `RemoteText.text` projection of
   `content`. A mismatch, an unsafe or oversized answer, a non-object or
   invalid JSON, or any 4xx but 408 and 429 rejects terminally; a network
   error, a timeout, a 408, a 429, or a 5xx raises
   `CommentFetcher::Unavailable`, so the item retries with the existing
   backoff;
7. create the row with `relayed_by_actor_id` = the sender,
   `relay_activity_uri` = the activity id, `confirmed_at` = now,
   `audience: public`, and no `activity_uri` (this instance never saw the
   author's `Create`); a race on the unique `uri` reloads the winner;
8. `Comments::Relink` (§7.2 step 6), then notify the local author of the
   parent comment when the relayed comment is a reply to them (§10); the
   note's owner is not local.

`Undo(Announce)` → `Inbox::CommentRelayUndo`: resolve the comment by
`relay_activity_uri` from the nested object's `id`, falling back to
`Comment.find_by(uri: object["object"])`; an unknown comment is a no-op; the
sender must be the thread note's actor (the host); a non-active comment is a
no-op. This instance's own comment becomes `removed` with reason `owner` and
keeps its words for its author — the host's `Reject` reason `removed` says the
same, whichever arrives first. A third party's relayed copy becomes `removed`
with reason `unknown` and loses its words (`Comment.scrubbed_text`): the host
undoes a relay when the author deleted the comment, the owner removed it, or
the author was blocked or deleted, this instance cannot tell which, and the
words were never its own to keep; its stub reads « Commentaire retiré. ».
Notifications are withdrawn either way.

### 7.6 Withdrawals

| Trigger | Effect on comments |
|---|---|
| `Federation::Safety::Blocking#withdraw_entitlements!` (actor or domain block) | every active comment authored by the blocked actors becomes `removed` / `blocked`, on local threads and on received threads; notifications are already withdrawn by `Notifications::Withdraw.new(actor:)`; unblocking restores nothing |
| `Federation::Inbox::Delete#process_actor_deletion!` (remote author gone) | that actor's active comments become `removed` / `actor_deleted` |
| `Federation::ActorDeletion` / `Users::DeleteAccount` (local account gone) | `Comments::AuthorRemoval` turns the account's active comments `removed` / `actor_deleted` and withdraws their notices in the transaction that tombstones the actor, before the user row is destroyed; the actor row survives tombstoned, so `actor_id` stays valid; remote copies are hidden by the actor `Delete` every peer the account's instance delivers to |
| all three, on a thread hosted here | `Comments::AuthorRemoval` also undoes the relay of each removed comment (`Outbox::CommentUnannounce`, §8.4) and leaves the `Undo`s on its `outbox_events`, which `Blocking`, `ActorDeletion`, and `Inbox::Delete` expand after their commit: an instance holding a relayed copy may never receive the author's own actor `Delete`, so the host tells it; a blocked recipient is still refused by the delivery path |
| local account deactivated (suspension, deletion window) | nothing on the rows: while it lasts, the card names the author « Un compte indisponible » with a neutral generated avatar and no handle or link, and the REST `author` is null; reinstatement names them again, and the purge removes the comments as above |
| unfollow, follow rejection, entitlement withdrawal | nothing on the rows: reading a received thread is gated by the note's policy, so a withdrawn note hides its comments; the rows go with the note row (`dependent: :destroy`) and `RemoteMedia::Purge` is unchanged |
| note tombstone (`Delete` of the publication) | the note page shows its tombstone; comments are hidden with it |
| publication withdrawal or replacement on the origin | the thread stays on the workout for the owner (§11.1); pending secondary events are cancelled (§9) |
| workout deletion | rows cascade with the workout; remote holders are told through the publication `Delete` they already receive |

### 7.7 Idempotency and ordering

- Admission is idempotent per `(recipient_actor, activity_uri)`; the handler
  is idempotent per comment `uri` and tolerant of redelivery.
- A `Delete`, `Reject`, or `Undo(Announce)` arriving before its `Create` or
  `Announce` is a terminal no-op for an unknown comment; Allure senders order
  them (§9), so this only happens when the first activity failed for good.
- The handler runs inside `FederationInboxItem.transaction` like the others;
  an `Inbox::Rejected` becomes `item.reject!`, any other error retries with
  the existing backoff.

## 8. Outbound processing

### 8.1 Reader's comment and its deletion

`Federation::Outbox::CommentCreate.new(comment:)` builds the
single-recipient event (`subject_type: Actor`, `audience: { "to" =>
[host.uri], "cc" => [] }`), the `ReactionLike` shape; `Comments::Post` stores
its `activity_uri` on the row. `Federation::Outbox::CommentDelete.new(comment:)`
builds the `Delete` with the Tombstone object (`deleted` = the row's
`deleted_at`, so the payload is stable) for the attempted set of the
comment's `Create`, cancels that `Create`'s unattempted deliveries, and
creates nothing when no attempt was made.
`Federation::Outbox::CommentSendability` makes a comment's `Create` stop with
its comment: expansion cancels the event and delivery cancels the POST once
the comment is no longer active, so a comment deleted before its `Create`
left never leaves. `RecipientAuthorizer#authorize_actor_event_recipient`
needs only a safe inbox, and `Deliver#wait_for_predecessor?` orders the
`Delete` after the `Create` by `object_uri`. `Comments::Outbound.enqueue!`
expands every intent after commit.

### 8.2 Owner's comment and its deletion

The same builders with `subject_type: "WorkoutPublication"`,
`subject_id`/`workout_publication_id` = the active publication, `audience` =
the publication's `to`/`cc` (public: `[#Public]` / `[followers]`; followers:
`[followers]` / `[]`). The `Delete` audience is the attempted set of the
comment's `Create` (`PublicationWithdrawal.recipient_uris_for` applied to
that event).

### 8.3 Host's `Reject`

`Federation::Outbox::CommentReject.new(host_actor:, author_uri:,
create_activity_uri:, comment_uri:, reason:)` — `subject_type: Actor`,
`object_uri` the host actor URI, `audience: { "to" => [author.uri] }`, one
idempotency key per reason and comment (`comment:reject:<reason>:<uri>`), so
a refusal at receipt and a later removal never collide. Created inside the
inbox transaction (pushed on `processor.outbox_events`) or inside
`Comments::Remove` for a remote author.

### 8.4 Host's `Announce` and `Undo(Announce)`

`Federation::Outbox::CommentAnnounce.new(comment:, publication:)` —
`subject_type: "WorkoutPublication"`, `object_uri` the host actor URI, so the
activity identity is minted on the host's authority even for a remote
author's object; the idempotency key `comment:announce:<comment uri>` makes
that identity deterministic (`CommentAnnounce.activity_uri_for`), so the
withdrawal finds it with no column on the host's row. The payload is
`{type: Announce, actor: host, object: <the comment, §6.6>, to: [#Public],
cc: [host/followers]}`; a followers publication raises. `Inbox::
CommentReceipt` pushes it on `processor.outbox_events`, and `Comments::Post`
creates it in the comment's transaction for a member's comment on a public
workout.

`Federation::Outbox::CommentUnannounce.new(comment:)` runs when a comment
leaves a thread hosted here — `Comments::Delete`, `Comments::Remove`, the
inbound `Delete`, `Comments::AuthorRemoval` — inside that transaction: it
finds the `Announce`, cancels its unattempted deliveries, redacts its payload
(`Outbox::PayloadRedactor`), and, when an attempt was made, builds the `Undo`
(`comment:undo-announce:<comment uri>`) addressed to that attempted set. A
relay that never left produces no `Undo`. Both are secondary publication
events (§9) and inherit their authorization, ordering, and cancellation;
`Outbox::CommentSendability` stops an `Announce` whose comment left (its
redacted payload no longer names an active comment), and the actor's outbox
collection hides it (`FederationOutboxEvent.without_withdrawn_comments`).

## 9. Secondary publication events — transport extension

`Federation::Delivery::RecipientAuthorizer`, `Federation::Outbox::
Expander`, `Federation::Delivery::Deliver`, `Workouts::PublicationWithdrawal`
and `Workouts::PublicationReplacement` assume that an event with a
publication subject *is* the publication: its `object_uri` is the note's and
its `Create` is the one that fans out. An owner's comment `Create`, an
`Announce`, and the `Invite` of [`SHARED-ACTIVITIES.md`](SHARED-ACTIVITIES.md) are **secondary**:
publication subject, different `object_uri`. The extension is stated here so
the two contracts share it:

1. **Secondary** — a publication-subject event whose `object_uri` differs
   from its publication's `object_uri`. The check is a lookup in the code
   that needs it (`RecipientAuthorizer#secondary_event?`,
   `Expander#secondary_publication`, `Deliver#secondary_predecessor`), not a
   column.
2. **Recipients.** `RecipientAuthorizer`: a secondary `Create` or `Announce`
   is delivered only to a recipient of the *publication's* `Create` (found by
   `PublicationWithdrawal.find_create_event`) whose delivery holds or is
   about to hold the note — recipient `authorized`, delivery `pending`,
   `delivering`, `reconciling`, `retrying`, or `delivered` — **and** who still
   passes the publication rules (`follow_accepted?`, `capability_allowed?`,
   `policy_allowed?`). A failed or cancelled publication delivery takes the
   recipient out at the next reauthorization. A secondary `Delete` keeps
   today's rule — the attempted set of its own `Create` by `object_uri` — and
   a secondary `Undo` goes to the attempted set of the activity it undoes,
   found through the nested object's `id` among the same actor's events
   (`RecipientAuthorizer.undone_event_for`); an `Undo` whose activity cannot
   be found reaches nobody. Each withdrawal goes exactly where its
   `Create`/`Announce` went. The publication's recipients, not the current
   follower list, are the right audience: a follower accepted after the
   publication never received the note and would reject the comment
   terminally.
3. **Expansion.** The publication's recipients exist only once its own
   `Create` expanded. `Expander` leaves a secondary `Create` or `Announce`
   pending while that `Create` is still `preparing` (route image) or
   `pending`, and the publication `Create`'s own expansion enqueues every
   pending secondary `Create` and `Announce` of the publication again, so an
   owner who comments right after publishing is not left to the five-minute
   recovery sweep.
4. **Ordering.** `Deliver#wait_for_predecessor?` also makes a secondary
   `Create` or `Announce` wait until the publication `Create`'s delivery to
   that recipient is terminal; a secondary `Delete` keeps waiting for its own
   `Create`, and a secondary `Undo` waits for the activity it undoes (only a
   publication-subject `Undo`: an actor's `Undo` of a follow or a like keeps
   its unordered delivery). Without this a comment can arrive before the note
   and be lost to a terminal rejection, the ordering defect already
   identified for the deferred `Invite`.
5. **Sendability and cancellation.** `Deliver#event_sendable?` and
   `Expander#publication_create_no_longer_sendable?` already require the
   active publication for any publication-subject `Create`, which covers a
   secondary one; `Delete` and `Undo` need only the retained identity. A
   withdrawn, replaced, or taken-down publication therefore stops its
   secondary events lazily — the unexpanded event is cancelled at expansion,
   a queued delivery at its next attempt — with no sweep in the withdrawal
   transaction. The `Announce` joins the same rule.
6. **Presentation.** `Workouts::DeliverySummary`,
   `Workouts::RenderPublicationRouteImageJob` (which releases the `preparing`
   intent), and the operator's `Admin::Publications::DeliveryRollup` read only
   the publication's own `Create` (by its `object_uri`); secondary events
   never change the publication's displayed state, and a comment `Create`
   can never be mistaken for the intent waiting on the route image.
   `Workouts::PublicationPreflight` accepts a `Create` or `Delete` whose
   object is a local comment URI under a publication or an actor subject,
   and an `Announce` or `Undo` under a publication subject whose object is
   its own actor's URI (the host's relay), checked structurally because the
   comment row goes with its workout while the event stays. In the actor's
   outbox collection (`Federation::Serializers::OrderedCollection`) a public
   secondary event lists like any public activity; the
   `live_publication_creates` scope hides a secondary `Create` or `Announce`
   with its inactive publication, and `without_withdrawn_comments` hides
   either once its comment left.

The outbox integrity check `outbox_publication_subject_integrity` is
unchanged: a secondary event carries `workout_publication_id = subject_id`
like the note's own.

## 10. Notifications

One new kind, `comment`, with the `Comment` row as subject and the author's
actor as actor. Recipients:

- the owner of a local thread, for every comment by someone else;
- the local author of the parent comment, for a reply by someone else;
- never the comment's author; duplicates collapse on the unique
  `(user, kind, subject)` index (an owner replying to their own commenter
  produces one entry for the commenter).

Copy names the gesture: "a commenté votre activité « titre »" for the owner
(`notifications.kinds.comment`, `comment_untitled`) and "a répondu à votre
commentaire" for the author of the answered comment (`comment_reply`). The
reply copy never carries a title: its recipient may not be allowed to read
the source title the owner sees. A notice whose comment no longer exists
reads "Ce commentaire n'est plus disponible" (`comment_deleted`) and opens
the inbox. Opening the entry lands on the comment's anchor on the workout
page (on the received-note page from §11.2). `Comments::Notifier` owns the
recipients and the withdrawal. Withdrawn by `Comments::Delete`,
`Comments::Remove`, `Comments::AuthorRemoval`, and by an inbound `Delete`,
`Reject`, or `Undo(Announce)`, plus the existing actor, block, and deletion
sweeps. Per-account switch `users.notify_comments`, on by default, added to
`Notifications::Create::PREFERENCES`, the settings form and its permit list,
`Notification::KINDS`, the `notifications_kind` check, and the notifications
contract ([NOTIFICATIONS.md](NOTIFICATIONS.md)) in the same patch.

## 11. Surfaces

### 11.1 Workout page — the comments card

Rendered in the full-width area of `workouts/show` (`DESIGN.md` §20.3
reserved "a section at the bottom of the workout detail page, after
Partage"): for the owner after the sharing and participants sections and
before the original data; for every other viewer as the last section. It
renders when the workout has an active publication, or when the viewer is the
owner and comments exist (a withdrawn publication keeps the thread readable
for the owner, composer absent). An unpublished workout with no comments
shows nothing: comments are a publication feature, and the page stays calm.

Anatomy (`comments/_section` → `comments/_card`, Turbo Frame
`comments-workout-<short id>`, section anchor `#comments`):

- header: the count as the title (« Commentaires », « 1 commentaire », « 3
  commentaires »); for the owner of a published workout, a ghost button
  « Fermer les commentaires » / « Rouvrir les commentaires » (`ti-lock` /
  `ti-lock-open`) submitting `PATCH /workouts/:id/comment_thread` — a plain
  button, so it works without JavaScript. It is absent when the snapshot's
  profile closed comments; the owner then reads « Le profil de publication
  « X » ferme les commentaires. Remplacez la publication pour les ouvrir. »;
- the thread (`comments/_comment`, each an `<article id="comment-<short
  id>">`): the avatar (`DESIGN.md` §9.5 component), the account's display name
  linking to its profile, its handle (`@marie`, or `@user@instance` for a
  remote author, `DESIGN.md` §24 rule 2: badged, not restyled), the posting
  moment as `smart_started_at` in a `<time datetime>`, the plain text through
  `simple_format(h(body))` (a remote author's sanitized HTML joins in the
  received-note card), and an action row of ghost buttons: « Répondre » on an
  active top-level comment when the viewer may write, « Supprimer » on the
  viewer's own comment, « Retirer » on someone else's for the owner; both go
  through the shared confirmation modal (`DESIGN.md` §10.10);
- replies hang one level under their root, behind a rule; a withdrawn root
  with visible replies is a muted stub « Commentaire supprimé par son
  auteur. » / « Commentaire retiré par le propriétaire de l'activité. » /
  « Commentaire retiré. » (`comments/_stub`), and a withdrawn root without
  them is not rendered. The author of a removed comment still sees it, muted,
  with « Retiré par le propriétaire »;
- « Répondre » toggles an inline reply composer under the root through a
  Bootstrap collapse (`data-bs-toggle="collapse"`, `aria-expanded`); the
  `comment-reply` Stimulus controller only moves focus into the textarea when
  the collapse opens, through a `data-action` binding Stimulus releases;
- the composer at the foot (`comments/_composer`): « Votre commentaire »,
  a textarea with `maxlength="2000"` and `required`, the mandatory privacy
  sentence (§12) as its description, and « Commenter » (« Répondre » in a
  reply composer, `btn-outline-primary`); Turbo's `data-turbo-submits-with`
  shows « Envoi… » while the frame is busy and the card dims. The closed state
  replaces the composer with « Les commentaires sont fermés sur cette
  activité. »; the owner of a withdrawn publication reads « Cette activité
  n'est plus publiée. Le fil reste visible pour vous seul et personne ne peut
  plus y écrire. »;
- empty state (open, no comment): « Pas encore de commentaire. À vous de
  lancer la conversation. »;
- a refused text re-renders the card with the text back in its composer —
  the reply composer reopened when it came from one — marked `is-invalid`
  with its `invalid-feedback` reason; a successful post re-renders the card
  with an empty composer and the new comment. No toast on any gesture: the
  thread is the feedback, and the owner hears about it through the bell.

Every mutation (`POST`, `DELETE`, `PATCH`) renders the card partial when the
request carries a `Turbo-Frame` header and otherwise redirects to the
thread's own page (`GET /workouts/:id/comments`) with a refusal as a flash
(`CommentCardRendering`, the `WorkoutReactionsController#render_bar`
pattern), so the page works without JavaScript and inside the iOS
companion's web views without any native affordance. A reader who can no
longer see the thread after the gesture (the author deleting a comment on a
withdrawn publication) gets an empty frame or the feed, never the thread.

Below `lg` the workout page hides the card (`d-none d-lg-block`) and its
social row — inside the page header, `comments/_social_row`,
`DESIGN.md` §10.17, §20.3 —
leads with a button to the thread's own page: `WorkoutCommentsController#index`
renders the same card alone under a way back to the workout, for exactly the
readers `CommentCard#visible?` admits, and 404 for anyone else. The feed's
count pill and the comment notifications open that page
(`comment_thread_path`), on every screen.

### 11.2 Received note page

The same card (`comments-remote-note-<id>`) after the media frame and before
the mandatory provenance line of `DESIGN.md` §20.16. The composer appears for
a signed-in member when `RemoteNotePolicy :comment` allows it; the viewer's
own comments carry their state when it is not plain: « Refusé : les
commentaires sont fermés » / « Refusé par le propriétaire » (`rejected`, by
reason), « Retiré par le propriétaire » (`removed`). There is no pending
state: a followers thread is never relayed and a host older than the relay
never announces, so a pending label could stay forever over a comment the
host took; a refusal is the only signal and it arrives as a `Reject`. Other
readers' comments relayed by the origin appear like any comment, their
handle naming their instance. A tombstoned note shows its tombstone and no
card. Below `lg` the note page carries the same social row and its thread's
page is `GET /remote_notes/:id/comments` (404 for a deleted note).

### 11.3 Feed and profile note lists

`feeds/_item` gains a count pill — the reaction pill atom (`DESIGN.md`
§10.17) with `ti-message-circle` and the number, `aria-label` « 2
commentaires », tooltip « Voir les commentaires » — leading the
right-aligned row of the reaction bar and linking to the thread's own page
(§11.1). It renders only when the count is positive (a card never
offers a gesture its reader cannot complete there; the composer lives on the
page) and is lifted above the card's stretched link like the bar. The count
comes from `comment_count_for(item.record)`, memoised over `@comment_targets`
like `reaction_summary_for` (`FeedsController`, `RemoteProfilesController`).

### 11.4 Settings and profiles

- `/settings/notifications`: the « Commentaires » switch with its hint.
- The publishing-profile form: the `comments` checkbox among the other
  settings, hint « Permet aux personnes qui voient la publication de la
  commenter. Le choix est annoncé aux autres instances ; vous pouvez aussi
  fermer le fil d'une activité à tout moment depuis sa page. ». The profile
  page lists « Commentaires : Ouverts / Fermés », and the candidate preview
  states « Commentaires fermés par ce profil. » when the selected profile
  closes them. The publish preview's field list does not name comments: they
  are not shared data.

### 11.5 Routes

```ruby
resources :workouts do
  resources :comments, only: %i[index create], controller: "workout_comments"
  resource :comment_thread, only: :update, controller: "workout_comment_threads"
end
resources :comments, only: :destroy
get "/remote_notes/:id/comments", to: "remote_note_comments#index", as: :remote_note_comments
post "/remote_notes/:id/comments", to: "remote_note_comments#create"
get "/api/v1/comment/:id", to: "federation/comments#show", as: :comment_object
```

Controllers scope through the current account: `Workout.find_by_short_id!`
for workouts, `RemoteNote.find` behind `Allure::Federation::Config.enabled?`
for notes, `Comment.find_by_short_id!` then the service's own authorization
for destruction. `NotAllowed` maps to 404; `Invalid` re-renders the card with
the field error (422 inside the frame); `Closed` — the owner closed the
thread while the reader was typing — re-renders the card in its closed
state, so the reader sees the sentence instead of an error page.

### 11.6 Styles and copy

`app/frontend/styles/components/_comments.scss` holds the thread indentation,
the stub, and the state badges on the existing tokens; nothing per-sport.
Locale keys live under `comments.*` (`title`, `count`, `empty`, `closed`,
`closed_by_profile`, `composer.*`, `actions.*`, `states.*`, `stub.*`,
`privacy.*`) plus `notifications.kinds.comment*`, `settings.notifications.
comments_*`, and the profile setting labels, in `fr.yml` and `en.yml`
together.

## 12. Privacy-critical copy

Added to `DESIGN.md` as §19.21 "Comments — on the composer and the closed
thread", mandatory verbatim sentences:

| Where | FR | EN |
|---|---|---|
| composer, public local publication | Votre commentaire est visible par toutes les personnes qui voient cette activité, ici et sur les autres instances qui l'ont reçue. | Your comment is visible to everyone who can see this workout, here and on the other instances that received it. |
| composer, followers-only local publication | Votre commentaire est visible par les personnes qui suivent ce compte, ici et sur leurs instances. | Your comment is visible to the people who follow this account, here and on their instances. |
| composer, received public note | Votre commentaire est envoyé à l'instance de @handle, qui le transmet aux autres instances qui ont reçu cette activité. Le supprimer ici en demande la suppression partout, sans garantie. | Your comment is sent to @handle's instance, which passes it on to the other instances that received this workout. Deleting it here asks for its deletion everywhere, without guarantee. |
| composer, received followers-only note | Votre commentaire est envoyé à l'instance de @handle, qui en conserve une copie. Le supprimer ici en demande la suppression là-bas, sans garantie. | Your comment is sent to @handle's instance, which keeps a copy. Deleting it here asks for its deletion there, without guarantee. |
| closed thread | Les commentaires sont fermés sur cette activité. | Comments are closed on this workout. |

The words follow the glossary (`DESIGN.md` §4): « activité » / "workout",
never « sortie » or "activity". The two local sentences state the federated
reach of the relay: a sentence that names a wider audience than the current
path reaches errs on the safe side and never has to change under a reader's
eyes. A received public note's sentence names the origin and the instances it
passes the comment on to; a followers note, never relayed, keeps the
origin-only sentence.

Nothing names the protocol (`DESIGN.md` §24 rule 1): "l'instance de @handle",
never "the remote actor"; "envoyé", never "delivered as an activity".

## 13. Lifecycle interactions

| Situation | Behaviour |
|---|---|
| Delayed publishing (`scheduled`) | not active: no card for others, no composer for the owner |
| Republishing | the thread stays on the workout; new owner comments reference the new `object_uri`; remote holders of the new note start empty; comments naming the old object get `Reject` reason `inactive` |
| Withdrawal, operator takedown | pending secondary events cancelled (§9); the owner still reads the thread, nobody can post |
| Workout deletion | rows cascade; peers hide the thread with the note tombstone |
| Profile change | future publications only, like every setting; the live switch is the owner's tool in between |
| Account suspension (`/admin`) | nothing on rows; a suspended account cannot sign in to post |
| Participations ([`SHARED-ACTIVITIES.md`](SHARED-ACTIVITIES.md)) | no interaction: a participant comments like any member who sees the publication |
| Reactions | independent rows; a comment never changes a count |

## 14. Tests

- **Model**: single-target, status, audience, reason, and body-length checks
  at both boundaries; `parent_is_a_root_on_the_same_thread`; readonly
  attributes; state transitions idempotent.
- **Policies**: the `:comment` matrix of §4.1 for every principal and
  audience, `comments_open?` with the snapshot flag and the live switch,
  `RemoteNotePolicy :comment` with `comments_closed`.
- **Services**: post as owner, member, follower (flag on/off), anonymous;
  reply to a root, to a reply (refused locally), to another thread; blank,
  too long, control characters; closed, profile off, inactive, full; delete
  by author, remove by owner, each withdrawing notifications and creating the
  right intent; close/reopen; `Thread` ordering, stubs, and per-viewer
  states; `Counts` query count on a feed page.
- **Serializer and parser**: a pinned `CommentNote` fixture; the
  `RemoteComment` rejection matrix (type, id authority, attributedTo,
  inReplyTo, content, size), sanitization, text projection cap, relay mode.
- **Inbox**: `Inbox::CommentReceipt` for each thread resolution branch,
  flattening, authorization refusals with their `Reject` reason, idempotency
  and tombstone-wins, race on `uri`, relink; `Delete` comment branch and the
  unknown-URI deviation; `process_reject` comment branch; `CommentRelay` with
  a stubbed fetch for match, mismatch, 404, retryable failure, blocked
  author, foreign or followers thread, the received-thread bound, own-comment
  confirmation, orphans and their adoption, idempotency, and
  `CommentRelayUndo` for a third party's copy, an own comment, a forged
  sender, and an unknown relay.
- **Outbox and delivery**: event identities and payloads; §9 — attempted set
  versus current followers, ordering after the publication `Create`,
  cancellation on withdrawal and replacement, sendability per type, delivery
  summary unchanged; the reader's `Delete` after its `Create`; the
  `Announce` of a member's and of a remote reader's comment, never on a
  followers thread, its `Undo` only where it was attempted and after it, the
  relay withdrawn by deletion, removal, block, and account deletion, the
  outbox collection, and the preflight.
- **Requests**: each route inside and outside a Turbo Frame, anonymous
  redirect, 404 for every denial, 422 re-render, the owner switch, the feed
  pill, the received note card, the object endpoint for public, followers,
  deleted, and unknown comments.
- **Notifications**: one entry per recipient, author excluded, both copies,
  withdrawal on every path, the settings switch.
- **Safety**: block and domain block sweep, remote and local actor deletion,
  rate limiter unchanged.
- **Ring**: the comment phases of `dip fed_test` and `dip fed_restricted_test`,
  including the relay, the confirmation, the unrelay, the refusal and the
  object endpoint.

## 15. Out of scope

Mentions (`Mention` tags are already preserved in `raw`); comments on
courses; reactions on comments; thread backfill on republish (the host
re-announces the thread to the new note's recipients); relay of
followers-only threads with host-vouched entitlement; showing the author that
the host took their comment, once every thread is relayed (`confirmed_at` is
already recorded); operator moderation of individual comments and a `/admin`
panel that would unlock comment metrics; external-peer reply interoperability
(Mastodon replies carry `#Public` and the author's followers in their
audience, which admission would spread to every local follower of the author;
an external dialect needs its own admission rule).
