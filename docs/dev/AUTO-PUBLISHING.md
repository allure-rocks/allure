# Automatic publishing contract

The opt-in that lets a publishing profile publish every new import by itself,
once the workout's enrichments have settled. It is off by default and never
retroactive.

## 1. Scope

A publishing profile may be marked **automatic**. Every workout imported
afterwards is then published with that profile — through the same
`Workouts::Publisher` as a publish by hand, so the same privacy preparation,
fail-closed refusals and safety delay (`DELAYED-PUBLISHING.md`) apply: without a
delay the publication goes live, with one it is `scheduled` and the owner keeps
publish now, reschedule and cancel.

The option is **off by default**, on every profile, built-in or custom. Turning
it on requires an explicit acknowledgement in the same submission. It is never
retroactive: only workouts imported while a profile is automatic count.

Course publications (`SegmentPublication`) are out of scope.

## 2. Data model

`publishing_profiles`:

- `auto_publish` boolean, default false;
- `auto_publish_exclude_commute` boolean, default false;
- `auto_publish_excluded_sports` text array of catalog slugs, empty by default:
  the sports whose workouts are never published by themselves, like commutes.
  An empty list excludes nothing, so every existing automatic profile keeps
  publishing every sport. The model drops blanks and duplicates, sorts the list,
  and refuses a slug the catalog does not know;
- partial unique index `(user_id, audience) WHERE auto_publish`, mirrored by a
  model validation: **at most one automatic profile per audience** and account,
  because a workout carries at most one live publication per audience
  (`PUBLISHING.md`). A public and a followers profile may both be automatic;
- the virtual `auto_publish_acknowledged` attribute: turning `auto_publish` on is
  invalid without it; an already automatic profile saves without it;
- an unpublishable profile (followers while restricted federation is off) cannot
  be turned on.

Restoring a built-in profile's defaults turns automatic publishing off and
clears its exclusions.

`workout_auto_publications` — one ledger row per imported workout and audience:

| column | meaning |
|---|---|
| `workout_id` | cascade on delete |
| `publishing_profile_id` | nullified when the profile is deleted |
| `workout_publication_id` | the publication it made, nullified with it |
| `audience` | the profile's audience at import, unique per workout |
| `status` | `waiting` → `published` / `skipped` / `failed` |
| `reason` | why nothing was published (skipped and failed only) |
| `detail` | the publisher's refusal message, bounded to 500 characters |
| `deadline_at` | import time + 6 hours |
| `settled_at` | NULL exactly while `waiting` (check constraint) |

The ledger is owner-only bookkeeping. It never enters a snapshot, a
representation or federation, and the wire contract is unchanged.

## 3. Enrolment at import

`Workouts::Importer` calls `Workouts::AutoPublicationEnrollment` after the
workout is persisted and its enrichments are enqueued. A failure is reported and
never fails the import; a duplicate creates no workout and no row. For each
automatic profile one row is created, already `skipped` when:

| reason | rule |
|---|---|
| `bulk_import` | a file batch of more than 5 entries (the frozen total, known before the first import), a remote batch with the `manual` trigger (a date-range retrieval), or a Strava archive |
| `stale` | the workout started more than 7 days before the import |
| `commute` | the workout is a commute and the profile excludes commutes |
| `sport` | the workout's sport is in the profile's excluded sports |
| `profile_unavailable` | the profile's audience cannot be published here |

Single uploads, small file batches (iGPSPORT included), the hourly sync and
webhooks are not bulk. Otherwise the row is `waiting` and
`Workouts::AutoPublishJob` is enqueued.

A bulk import's enrichments — and everything they enqueue in turn — run at the
backlog priority (`BacklogPriority::PRIORITY`, 10; the default is 0): Solid Queue
runs ready jobs and releases jobs held by a concurrency limit by ascending
priority, so a new outing's route image, places and matching pass ahead of a
history being imported.

## 4. Readiness

`Workouts::AutoPublicationReadiness` waits for every enrichment the import
started, each read from its own derivation marker (`[devdoc:derivations]`):

- **elevation** — `workouts.elevation_source_requested` is blank. The importer
  records `dem` when it enqueues terrain elevation; applying it (`Reanalyzer`)
  or giving up (`ApplyElevationSourceJob`) clears it, which the workout page
  also shows as the pending state;
- **segments** — `loop_reuse_version` is current. A reanalysis resets it to 0
  because new track segments invalidate every point-indexed effort, so a
  terrain profile is matched again before publishing;
- **places** — the toponymy exists and is not `pending` (virtual sports have
  none);
- **route_image** — `route_image_version` is current.

A failed enrichment counts as settled: waiting will not improve it.

## 5. Settlement

`Workouts::AutoPublishJob` (one at a time per workout) runs
`Workouts::AutoPublisher`, which only touches `waiting` rows:

- not ready and before the deadline: nothing happens;
- not ready past the deadline: `failed` / `enrichment_timeout`;
- ready: each row is re-checked — `skipped` with `profile_disabled` when the
  profile was turned off or deleted, `profile_unavailable`, `commute` when the
  owner marked it a commute meanwhile on an excluding profile, `sport` when the
  workout's sport became excluded meanwhile (a sport change re-runs the analysis,
  which wakes the job), or `already_published` when the audience already holds a
  live publication — then published through `Workouts::Publisher` → `published`.
  A `PublicationError` (an endpoint mask no zone covers, an unpublishable route)
  becomes `failed` / `publication_refused` with the message as `detail`; an
  unexpected error is reported and becomes `failed` / `error`.

Every enrichment job nudges the job when it finishes (`AutoPublishJob.nudge`, one
indexed lookup when nothing waits): the route image, the segment matching, the
toponymy (success and exhausted retries), and the elevation request being
cleared. `Workouts::AutoPublicationSweepJob` runs every 10 minutes in production
and re-runs the 500 workouts waiting longest, recovering a lost nudge and
applying the deadline. A suspended account publishes nothing.

The owner may decline a waiting row from the workout page
(`DELETE /workouts/:id/auto_publication`): `skipped` / `cancelled_by_owner`.

## 6. Notifications

Two actorless kinds, each with its own switch in `/settings/notifications` (on by
default):

- `auto_published` (`users.notify_auto_published`) — subject the publication,
  payload the audience and, for a delayed one, `scheduled_for`. The text says
  whether it is live or scheduled and until when. A delayed one still sends
  `publication_activated` when it goes live.
- `auto_publication_failed` (`users.notify_auto_publication_failed`) — subject
  the ledger row, payload the reason.

Both open the workout's sharing section.

## 7. Informing the owner

- **Profile form** — an « Publication automatique » card: the §19.25 notice, the
  switch (disabled with the holder's name when another profile of the audience
  is automatic), « Ne pas publier automatiquement les trajets », the sport
  exclusion pills (every active sport, the workout list's own
  `form-selectgroup`; none ticked excludes nothing), and the acknowledgement
  checkbox while the profile is not yet automatic.
- **Profile list** — an « Automatique » badge; above the table, the introduction
  of the option while no profile is automatic, otherwise the active notice.
- **Profile page** — the delay, the automatic state and the exclusions.
- **Import surfaces** — `/workouts/import`, `/workouts/new`, `/connections` and
  each service's page carry the active notice while a profile is automatic: each
  profile, its audience, delay and exclusions, the rules and a link to the
  profiles.
- **Import progress** — each imported entry states its automatic publication per
  audience: waiting, published, scheduled with its date, or not published with
  its reason.
- **Workout page** — the sharing card leads with each waiting row and its « Ne
  pas publier » action, states why a row did not publish (unless the owner
  declined it or the audience is published), and marks a publication or a
  scheduled publication made automatically.

## 8. Constants

`WorkoutAutoPublication::RECENT_WINDOW` (7 days), `BULK_FILE_ENTRIES` (5) and
`ENRICHMENT_DEADLINE` (6 hours) are the only tunables; every user-facing sentence
interpolates them.
