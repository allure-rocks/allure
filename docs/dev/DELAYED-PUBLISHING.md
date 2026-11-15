# Delayed publishing contract

The optional safety delay between an owner's publish action and any reader or
remote peer seeing the workout. Publishing is immediate by default; a profile
may opt into a hold, and the owner may override it for one publish.

## 1. Scope

The `immediate` preset (0) is the profile default and the first choice on the
publish form: `Workouts::Publisher` activates the publication in the request
path, exactly like publishing before the delay existed. A profile may instead
opt into a safety delay (1 day, 3 days, 1 week, 2 weeks, 1 month), overridable
per publish with the same presets.

With a delay, `Workouts::Publisher` and `Workouts::PublicationReplacement`
create the frozen sanitized snapshot in the `scheduled` state: nothing local
references it, no ActivityPub `Create` exists, and no media endpoint answers for
it. After the delay it activates automatically. During the window the owner
can:

- **Publish now** — activate immediately, after a deliberate second action;
- **Reschedule** — move the planned moment to another preset;
- **Cancel** — go straight to the terminal `deleted` state with no Delete
  activity, because no peer ever learned the object URI.

The delay is a protection the owner chooses; without it a publication is shared
immediately and irrevocably, and the §19.1 preview remains the pre-publish
check.

Course (`SegmentPublication`) parity is deliberately deferred; the workout path
proves the contract first.

## 2. Lifecycle

```text
unpublished -> published -> deleted          (default, immediate)
unpublished -> scheduled -> published -> deleted
                    \------------------> deleted
```

`WorkoutPublication::ALLOWED_TRANSITIONS` is the single transition map:
`scheduled -> active`, `scheduled -> deleted`, `active -> deleted`. `deleted` is
terminal. One row may be `active` or `scheduled` per workout and audience
(`PUBLISHING.md`), enforced by the
`index_live_workout_publications_on_workout_and_audience` partial unique index
and the mirrored model validation; each audience's publication has its own
delay.

`published_at` keeps its NOT NULL semantics: a scheduled row carries the planned
moment, and `WorkoutPublication#activate!` rewrites it to the actual activation
instant. That write is the controlled immutability exception for the state
change, the same class of exception as `attach_sanitized_route_image!`;
`scheduled_for` retains the planned moment for audit. A scheduled publication
was never externally visible, so nothing observable changes except going live.

## 3. Data model

`workout_publications` additions (`PUBLISHING.md` §7):

- `scheduled_for` (timestamp, required iff `status = 'scheduled'`, retained on
  active and cancelled rows);
- the deletion-state check treats `scheduled` like `active`: no `deleted_at`,
  source workout required;
- partial index on `scheduled_for` for the activation sweep.

`publishing_profiles.publish_delay_seconds` (integer, default 0, checked against
the preset list `0 / 86 400 / 259 200 / 604 800 / 1 209 600 / 2 592 000`) is a
policy column, **not** a `profile_snapshot` setting: the published
representation stays byte-identical, no federated payload changes, and existing
snapshots are never rewritten.

`users.notify_publication_activated` (boolean, default on) is the preference for
the activation notification.

## 4. Services and jobs

- `Workouts::Publisher` accepts `delay:` (a preset, defaulting to the profile
  value). With a delay it creates the `scheduled` row, attaches the sanitized
  media, pre-renders the route image during the window, and enqueues
  `Workouts::ActivateScheduledPublicationJob.set(wait_until: scheduled_for)` on
  the `default` queue; no outbox event is created. With `immediate` it creates
  the same frozen row and activates it through `ScheduledPublicationActivation`
  in the request path, with the activation job enqueued first as a fallback.
- `Workouts::ScheduledPublicationActivation` activates one publication: lock,
  no-op unless still scheduled, wait while the owner's deletion window is open
  (`[devdoc:account]`), defer when the job fires before `scheduled_for`,
  otherwise `activate!`, create the `Create` intent (`preparing` only while the
  route image is still rendering), enqueue expansion, and notify. `forced:`
  backs the owner's Publish now.
- `ScheduledPublicationActivation.sweep` runs from the recurring
  `Federation::RecoveryJob` next to the outbox recovery, so instance downtime or
  a lost enqueue activates due publications — delayed, never stranded.
- `Workouts::RenderPublicationRouteImageJob` attaches the image on a scheduled
  publication without finalizing outbox work that does not exist yet.
- `Workouts::ScheduledPublicationCancellation` and
  `Workouts::ScheduledPublicationReschedule` back the two owner actions;
  `Workouts::PublicationReplacement` withdraws the current publication and
  schedules its replacement; `Workouts::WorkoutDeletion` cancels a scheduled
  publication in the same transaction as the destroy.

## 5. UI and copy

- The publishing profile form carries the delay preset (`immediate` first) and
  the explanation of both states.
- The publish form carries the same preset (preselected from the profile); the
  submit label follows the selection ("Publish" vs "Schedule publication"), and
  the §19.1 preview sentence stays.
- The sharing card shows a scheduled projection: badge, planned local moment,
  the frozen representation rendered read-only, and the three actions. Its
  reschedule select omits `immediate`, because Publish now already means that.
  `DESIGN.md` §19.19 is the mandatory copy.
- Copy must state that source, profile and privacy-zone changes do not alter a
  scheduled publication (§19.3, §19.4, §19.7 already say this for active
  publications).

## 6. Notification

`Notification::KINDS` gains `publication_activated`, produced by the activation
service with no actor (the owner caused it) and the publication as subject,
honoring `notify_publication_activated`. Only the automatic activation notifies:
the immediate publish and the owner's Publish now happen in front of the owner
and are silent. The bell, inbox and read flows are unchanged. The notifications
contract (`[devdoc:notifications]`) is amended in the same patch.

## 7. Admin and observability

`/admin` publications gains a `scheduled` status filter with the planned moment
and an operator cancel (audited). Metrics pick up `status="scheduled"` from
`WorkoutPublication::STATUSES` with no catalog change. The publication preflight
asserts scheduled rows carry `scheduled_for` and no outbox events.

## 8. Tests

Model transitions, validations, indexes and the controlled `published_at`
rewrite; Publisher immediate activation and scheduling; activation idempotency,
early deferral, forced activation and the recovery sweep; cancellation,
rescheduling, replacement and workout deletion; scheduled invisibility in
feeds, media endpoints and `PublicationPolicy`; notification producer,
preference and rendering; request coverage for the three actions and the card
states; admin and metrics.

## 9. Out of scope

Course publications, per-publish free-form dates, email and Web Push.

An automatic profile (`AUTO-PUBLISHING.md`) applies its delay exactly like a
publish by hand: the automatic publication is created `scheduled` and keeps the
three actions.
