# Reactions contract

A workout is appreciated with one fun gesture instead of a generic like:
**bière** (`beer`), **boisson énergisante** (`energy`), **café** (`coffee`), or
the neutral **j'aime** (`like`). The neutral type is also what an external peer
means by a plain ActivityPub `Like`, so nothing is lost in interpretation.

One reaction per account and target is active at a time. Repeating the same
type withdraws it; choosing another type withdraws the old one and creates a
new one, preserving the ActivityPub identity of each gesture.

`DESIGN.md` governs the visual component; where the two conflict on a data or
protocol contract, this document wins.

## 1. Data model

The former `federation_likes` table is renamed **`reactions`** (model
`Reaction`) and generalized.

| Column | Type | Constraints and meaning |
|---|---|---|
| `id` | bigint | primary key |
| `actor_id` | bigint | not null reacting actor (local or remote) |
| `workout_id` | bigint | nullable local workout target, FK cascade |
| `remote_note_id` | bigint | nullable received-note target, FK cascade |
| `kind` | string | not null `beer`, `energy`, `coffee`, `like`; default `like` |
| `uri` | text | not null unique activity identity (see §3.3) |
| `audience` | string | not null `public` or `followers`: the audience the reaction is named to (see below) |
| `undone_at` | datetime | nullable withdrawal instant |
| timestamps | datetime | Rails audit columns |

- Check `reactions_single_target`: exactly one of `workout_id`,
  `remote_note_id`.
- Check `reactions_kind`: the four types.
- Check `reactions_audience`: `public` or `followers`.
- Partial unique index `(actor_id, workout_id) WHERE undone_at IS NULL`, and
  the same for `remote_note_id`.
- Existing rows keep their identity and take the neutral `like` type.

A reaction targets the **workout**, not a publication identity: republishing
after withdrawal keeps the counts (the object is the same activity). A reaction
targeting a received note cascades away with the note row, never with an
entitlement withdrawal.

A reaction still remembers the **audience** it was given through, because a
workout may carry several publications (`PUBLISHING.md`) and naming a reactor
to a reader of another audience would disclose a follow the instance publishes
nowhere else. The audience is written once, at creation:

- a local reaction on a workout is `public` while a public publication the
  reactor may read is active — the gesture then reveals nothing about them,
  whichever version they were served — and otherwise takes the audience of
  the publication serving them (`Reactions::Toggle`);
- an inbound `Like` takes the audience of the publication its object names;
- a reaction on a received note takes the note's audience.

The count stays one per workout across audiences; only the names follow the
audience (§3.2). A switch to another type re-evaluates it with the new row,
and nothing is rewritten when publications change afterwards. Rows that
predate the column were classified fail-closed by `AddAudienceToReactions`:
`public` only when a public publication of the workout was live at the
reaction's `created_at`, `followers` otherwise.

## 2. Authorization

- Reacting requires a signed-in local account, a viewable target, and not
  being the target's owner. The owner reads counts only; an anonymous browser
  is redirected to sign-in (`ACCESS.md`).
- Local publications go through `Workouts::PublicationPolicy` with the
  `browser_user` principal and the `:react` resource: the audience gates
  (`public`, and followers-only behind the restricted-federation flag with an
  accepted follower) apply exactly as they do to viewing. `:like` stays the
  inbound ActivityPub gate and is unchanged.
- Received notes go through `Federation::RemoteNotePolicy` with `:react`: the
  note must be active and public or held through an active entitlement.
- Denial is 404, never 403, like every other unauthorized representation.
- Reactions are **never** part of a publication snapshot, a sanitized
  representation, or a remote representation: they are live social state read
  at render time.

## 3. Behaviour

### 3.1 The toggle

`Reactions::Toggle` is the single local write seam. One gesture:

1. raises `InvalidKind` on an unknown type;
2. authorizes the target (`NotAllowed`);
3. withdraws the active reaction of the same type, or withdraws the active
   reaction and creates a new one of the requested type;
4. mints the reaction identity, creates the outbound outbox intent for a
   received note, and keeps the owner's notification in step;
5. commits the row, its outbox intent, and the notification withdrawal in one
   transaction, then enqueues expansion after commit. A queue failure never
   rolls the gesture back; the recovery sweep owns pending events.

### 3.2 Reading

`Reactions::Summaries` computes one page's counts, each viewer's own active
type, and the newest reactors per type, with grouped queries over the page's
workout and note rows (two queries for counts, two for the viewer, two
window-ranked for the names), so a feed page never runs a query per card. The
names feed the pill's tooltip (§3.4): at most three per type, deleted accounts
filtered in the query, blocked actors in one batched check
(`Federation::Safety::Blocks.blocked_uris`), and deactivated local accounts
(suspended or inside their deletion window) when the actors load. On a
workout, the ranked query only keeps reactions of an audience the viewer may
read (`Workouts::ReadableAudiences`: the owner all, anyone else the audiences
of `WorkoutPublication.visible_to`) plus the viewer's own; every other
reaction still counts, unnamed. A received note's reactors are named to all
its readers, who hold the same entitlement. Reaction names are live social
state, read at render time: they never enter a publication snapshot, a remote
representation, or the REST response (which keeps `counts` and `mine`).

### 3.3 Wire contract

A reaction on a received note carries the URI of the ActivityPub `Like` that
will be delivered:

- activity `id` = `#{local_actor.uri}/activities/<uuid>`, computed by
  `Federation::Outbox::EventBuilder` from a per-gesture idempotency key, so the
  outbox event and its later `Undo` reference the same activity;
- `Like` payload: `type`, `actor`, `object` (the note's `object_uri`), and
  `_allure_reaction` with the type;
- audience `to: [note.actor.uri]`;
- withdrawal sends `Undo` whose nested object is `{ "type": "Like",
  "id": <reaction uri> }`;
- a purely local reaction has no protocol identity and receives a local URI,
  exactly like a local follow (`/local_reactions/<digest>`).

Receiving side (`Federation::Inbox::Processor`):

- a `Like` resolves the target through `WorkoutPublication.active` by
  `object_uri`; the addressed recipient is the publication's local actor
  (`Inbox::Admission`), not the object URI;
- `_allure_reaction` selects the type; an absent or unknown value is the
  neutral `like`, never a rejection;
- the like is idempotent per `(actor, workout)` and per activity URI;
- `Undo(Like)` withdraws the matching reaction and its notification, and is
  idempotent.

An unknown-reaction type from a future Allure version therefore degrades to
the neutral type instead of breaking the exchange; a future wire addition must
extend this document and `Reaction::KINDS` together.

### 3.4 The bar

The bar is one component (`reactions/_bar`) for a workout publication and a
received note, governed visually by `DESIGN.md` §10.17 and rendered on every
surface of §5. A signed-in entitled non-owner gets one toggle button per type;
the owner and every other reader get the non-zero counts as plain pills; a bar
with neither counts nor a possible gesture renders nothing. It lives inside a
Turbo Frame, so one gesture re-renders the bar alone, and a request without
JavaScript redirects back to the target.

A populated pill's tooltip names who reacted: the newest
`Reactions::Summaries::NAMES_LIMIT` accounts per type, the viewer as « Vous »
leading the list, then « et N autres personnes ». The owner of a workout reads
the gesture addressed to them (« Marie a trinqué à votre activité »); every
other reader reads it on this activity. A deleted, blocked or deactivated
account, or a reactor of an audience the reader may not read (§3.2), is never
named and its reaction counts among the other people; when nobody is left to
name, the sentence counts people (« 2 personnes ont trinqué à cette
activité »). An empty pill keeps the action tooltip (« Réagir : Bière »). The
names come from the page's batched summary (§3.2) and are never exposed
through the REST API, which keeps `counts` and `mine`.

## 4. Notifications

The reaction notice is one notification kind, `reaction`, kept as a single
digest per workout (`[devdoc:notifications]`): the `Workout` is its subject,
the newest reacting account its actor, and the payload counts the reactions:

- recounted for the owner of a local workout on a local reaction and on an
  inbound Like; a reaction on a received note notifies the remote author only
  through the delivered Like;
- recounted when a reaction is withdrawn or switched, and by the existing
  actor/block/deletion withdrawals, and removed once no reaction is left;
- per-account switch at `/settings/notifications` (`users.notify_reactions`,
  on by default), extending `Notification::KINDS`, the database check
  constraint, and the notifications contract in the same patch;
- copy names the gesture ("a trinqué", "a boosté", "a offert un café", "a
  aimé") and the workout title when it exists; several reactions name the
  newest account and count the others.

## 5. Surfaces

- **Feed card** (`feeds/_item`): the bar sits at the foot of the card body,
  above the stretched link. A signed-in non-owner gets the toggle buttons; the
  owner gets the non-zero counts only.
- **Workout page**: the same bar in the header for a signed-in non-owner of an
  active publication; the owner reads the counts.
- **Received note page**: the same bar; the policy already gated the page, so
  a signed-in reader may react.
- **Remote profile note lists** reuse the feed card, so the bar follows.
- A bar with no counts and no possible gesture renders nothing.
- The bar lives inside a Turbo Frame: a gesture re-renders only the bar, while
  a request without JavaScript redirects back to the target.
- Every surface renders the same bar and the same tooltip (§3.4).

## 6. Tests

- Model: kind and single-target constraints at the model and database
  boundaries, active uniqueness per target, withdrawal idempotency.
- Service: local create/withdraw/switch, self-reaction and unpublished refusal,
  followers-only reactability, remote note entitlement, outbound Like and Undo
  identity, expansion enqueue. The summary: counts and own type per target, the
  newest names per type capped at three, deleted and blocked reactors kept out
  of the names while still counted.
- Admission: a signed Like resolves the publication author; a Like whose
  object is not a local publication is refused.
- Processor: type from `_allure_reaction`, unknown-type fallback, owner
  notification, `Undo(Like)` withdrawal.
- Requests: toggle inside the Turbo Frame, redirect without it, anonymous,
  owner, unpublished, unknown type, both targets, bar rendering per audience,
  and the pill's tooltip per reader (owner, other member, « Vous », cap,
  received note, empty pill).
- Ring: `dip fed_test` proves the receiving account likes the received note,
  the Like delivers, and the origin stores the reaction and notifies its owner.

## 7. Out of scope

Course (segment) reactions, reactor avatars, complete reactor lists outside the
tooltip's names, live fan-out of counts, email or push, reaction metrics in
`[devdoc:metrics]`, retention of the reaction when its source workout is
deleted, and reactions to comments (`[devdoc:comments]` keeps them out).
