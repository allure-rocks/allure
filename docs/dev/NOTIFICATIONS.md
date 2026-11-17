# Notifications contract

A durable, per-account in-app inbox for directed events. It is deliberately
**not** a feed and **not** a gamification mechanic: no points, levels, or
leaderboard pressure (`DESIGN.md` §3). Email is out of scope, and the browser
only ever talks to its own instance. Push to the iOS companion is one more
delivery of the same rows ([PUSH.md](PUSH.md)).

## 1. Scope

The base kinds are:

| Kind | Recipient | Actor | Created when |
|---|---|---|---|
| `follow_request` | the followed local account | the requester (local or remote) | a pending `Following` is created, for a local target (`Federation::Follow#follow_local!`, `Federation::Inbox::Processor#process_follow`) |
| `follow_accepted` | the requesting local account | the accepting account | a local `Following` transitions to accepted (`Federation::FollowDecision`, inbound `Accept` in `Federation::Inbox::Processor#process_accept`) |
| `publication_activated` | the owner | none | a delayed workout publication goes live automatically (`Workouts::ScheduledPublicationActivation`) |

The actorless kind exists because the owner caused the event: the self-skip in
`Notifications::Create` only applies when an actor is present. The subject is
the `WorkoutPublication`; the notification is kept after a later withdrawal,
because the activation did happen. Immediate publishing and the owner's Publish
now are silent: the owner is acting in front of the page, only the automatic
end of a hold needs to reach the inbox.

## 2. Data model

`notifications` is recipient-scoped:

- `user_id` (recipient, FK cascade), `actor_id` (who caused it, FK nullify);
- `kind` (string, checked against `Notification::KINDS`);
- `subject_type` / `subject_id` (the relationship it describes — a `Following`
  today);
- `payload` (jsonb object, reserved; never carries coordinates, workout
  content, or remote HTML);
- `read_at` (cross-device read marker), timestamps.

A unique partial index on `(user_id, kind, subject_type, subject_id)` makes
every producer idempotent, including redelivered federation activities. The
inbox is capped at `Notification::MAX_PER_USER` (100): `Notifications::Create`
prunes the oldest rows after each insert, except the unread ones of the
`Notification::ACTIONABLE_KINDS` that still await a decision or a repair
(`follow_request`, `participation_requested`, `participation_suggested`,
`participation_link_suggested`, `import_connection_expired`,
`auto_publication_failed`, `webhook_disabled`). They count toward the cap but
are never pruned while unread, so a burst of reactions or comments cannot
erase a pending request; their own relationships keep them bounded.

## 3. Producers

`Notifications::Create` is the only write seam. It skips a suspended recipient
and actions on oneself, honors the recipient's preferences, reports and
swallows unexpected errors (a notification is a side effect of a relationship
change, never part of it), and never fails its caller.

The server is the only source: no client can mint a notification. A future kind
adds a `PREFERENCES` entry and a producer call at the service/job seam that
performs the underlying change — never an Active Record callback on a model
whose transaction is already the source of truth.

## 4. Withdrawal (privacy consequence)

`Notifications::Withdraw` removes entries whose relationship ended. It is
called from:

- `Federation::FollowDecision` — any decision removes the pending
  `follow_request` entry;
- `Federation::Unfollow` and inbound `Undo(Follow)` — a withdrawn local request
  removes its entry;
- `Federation::Safety::Blocking` — blocking an actor or authority removes
  everything it caused;
- `Federation::Inbox::Delete#process_actor_deletion!` — a tombstoned remote
  author's entries disappear with it.

A recipient is destroyed with their inbox (FK cascade). A deleted actor leaves
the row but clears `actor_id`; the renderer shows "a deleted account" rather
than a dead link.

## 5. Surfaces

- **Topbar bell** left of the account menu (`DESIGN.md` §10.16, §24). The
  trigger's `aria-label` carries the unread count; the badge is text and
  `aria-hidden`.
- **Badge poll** — `GET /notifications/badge`, 60 s, paused while the tab is
  hidden, `Cache-Control: no-store`. Only the badge's inner HTML is replaced,
  so Bootstrap's dropdown binding is untouched.
- **Dropdown** — a Tabler `dropdown-menu-card` with the latest 5 items, loaded
  through a Turbo Frame when the dropdown opens (a Stimulus controller sets
  `frame.src`), plus "mark all as read" and "view all". On phones the card is
  pinned as a near-full-width sheet under the topbar. Item links open the full
  page and opt out of Turbo prefetch, because opening reads the item.
- **`/notifications`** — a paginated list (Pagy 20) with `all` / `unread`
  filters, an empty state, and a read action per item. Opening a notification
  marks it read and opens its account or the `/people` decision hub.
- **`/settings/notifications`** — one switch per kind. A disabled kind is never
  created, so re-enabling it does not resurrect old events.

## 6. Copy

Both locales; sentence case; no protocol vocabulary. "X wants to follow you",
"X accepted your follow request"; the remote account keeps its shared avatar,
name, and `@user@instance` badge.

## 7. Out of scope

Mentions, record or leaderboard notifications, email, browser Web Push,
digests (other than the per-workout reaction digest of §8),
badges/XP, and notification federation. Comments and replies joined with
`COMMENTS.md` (§10). Course-record notifications stay deferred (`SEGMENTS.md`).
Each later kind must extend the `KINDS` check constraint and this contract in
the same patch.

Push to the iOS companion is a delivery of the same rows ([PUSH.md](PUSH.md)): a
new row, or a reaction digest turned unread, goes to the recipient's opted-in
devices through the relay, encrypted end to end. It adds no kind and no
preference besides the device switch and its « Masquer le contenu »; a kind
turned off here is never created, so it is never pushed.

## 8. Reactions

The `reaction` kind is one **digest per workout**: its subject is the owner's
`Workout`, its actor the newest account counted, and its payload
`{ "count" => n, "kinds" => { "beer" => …, … } }`. Sixty reactions make one
entry, not sixty. `Notifications::ReactionDigest` recomputes the row from the
active reactions every time, never incrementing: accounts that are tombstoned
or blocked are left out, and the row is locked before the recount so
concurrent reactions converge.

- Producers are unchanged: local reactions (`Reactions::Toggle`) and inbound
  Likes call `Notifications::Create` with the `Reaction` as subject. The
  `reaction.created` webhook still fires once per reaction; only the in-app
  write goes to the digest.
- A new reaction makes the digest unread again and moves it to the top
  (`created_at` is the latest alert). A switch of type by the same local
  account (`alert: false`) recounts silently; a remote switch arrives as an
  `Undo` then a `Like` and alerts like a new reaction.
- `Notifications::Withdraw` with a `Reaction` subject recounts the digest and
  removes it once nothing is left. An actor-wide withdrawal (block, inbound
  actor deletion) never deletes a digest: it recounts every digest the actor
  reacted to, so the other accounts stay in it. Deleting the workout removes
  its digest.
- Copy: one reaction names its gesture ("a trinqué", "a boosté", "a offert un
  café", "a aimé"); several read « Marie et 59 autres personnes ont réagi à
  votre activité « titre » ». Opening it lands on the workout.

The per-account switch is `users.notify_reactions`, on by default.

## 9. Participations

Three kinds carry shared activities: `participation_requested` (the invited
account is asked to confirm), `participation_suggested` (a detection asks both
accounts, each copy targeting its own confirm action), and
`participation_confirmed` (the confirming account tells the counterpart). The
subject is the `WorkoutParticipation` row and the actor is the counterpart
account; a source workout that no longer exists falls back to the generic
deleted copy and the inbox. One switch covers requests and suggestions
(`users.notify_participation_requests`), one covers confirmations
(`users.notify_participation_confirmed`), both on by default. Decline,
withdrawal, block, unfollow, account deletion, and source deletion withdraw the
entries through `Notifications::Withdraw`.

## 10. Comments

The `comment` kind carries a `Comment` row as its subject and its author as
the actor. `Comments::Notifier` addresses the owner of the workout hosting the
thread for every comment, and the local author of the answered comment for a
reply; the author never hears about their own words, and the unique index
collapses an owner who also wrote the answered comment into one entry. The
owner reads "a commenté votre activité « titre »"; the answered author reads
"a répondu à votre commentaire", without a title, because that reader may not
be allowed to see the source title. Opening the entry lands on the comment's
anchor; a comment that no longer exists reads "Ce commentaire n'est plus
disponible" and opens the inbox. Deletion by the author, removal by the owner,
and an account deletion (`Comments::AuthorRemoval`) withdraw the entries. The
per-account switch is `users.notify_comments`, on by default.

## 11. Connected services

`import_connection_expired` is actorless, carries the `ImportConnection` as its
subject and `{ "provider" => … }` as its payload, and reads « Garmin Connect
demande une reconnexion »; `import_connection_revoked` is the operator's
revocation (payload `{ "provider", "by" => "operator" }`, « L'administrateur a
révoqué votre connexion Garmin Connect »). Opening either lands on the
service's page under `/connections`. A successful link and an unlink
withdraw them. The per-account switch is
`users.notify_import_connections`, on by default, shown only while a remote
source is enabled or the account holds a connection.

## 12. Automatic publishing

Two actorless kinds tell the owner what an automatic profile did with an
import. `auto_published` carries the `WorkoutPublication` and reads « « titre »
a été publiée automatiquement », or « … sera publiée automatiquement le … »
when the profile's delay holds it (payload `audience`, `scheduled_for`).
`auto_publication_failed` carries the `WorkoutAutoPublication` row (payload
`audience`, `reason`) and reads « La publication automatique de « titre » n'a
pas abouti ». Both open the workout's sharing section. Each has its own switch,
`users.notify_auto_published` and `users.notify_auto_publication_failed`, on by
default.

## 13. Data export

`account_export_ready` is actorless, carries the `AccountExport` and reads
« L'archive de vos données est prête à être téléchargée »; it opens
`/settings/account`. It has no switch: the account asked for the export, so
telling it is part of the answer. Like every kind, it is skipped for a
deactivated account (suspended, or in its deletion window).

## 14. Tests

Model constraints and cap; `Create` idempotency, self/preference/suspension
skips; `Withdraw` scope; each producer creates exactly one entry and withdraws
it on decision, undo, block, and author deletion; request coverage for auth,
per-account scoping (404), read-on-open, mark-all-read, badge/menu partials,
and the settings toggles.
