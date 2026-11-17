# Manual-entry contract

A strength session, a class, a run whose watch died, an outing recorded
nowhere: the account still wants it in its totals, its statistics and its
equipment wear. A manual entry carries the figures its owner declares and
nothing else. This document defines the shape, the validation, the web and API
surfaces, what it counts for and what it never counts for.

## 1. Intent and non-goals

Non-goals, deliberately:

- no synthesized file: a GPX or TCX made from the form would feed the
  analysis two points at a constant speed, inventing best efforts, laps,
  intervals and records, and the « original file » would be a file nobody
  recorded;
- no drawn route and no position of any kind;
- no record, best effort, segment effort, lap, split, smart lap, anomaly,
  place, toponymy, terrain elevation, route image, co-presence detection or
  participation;
- no publication or federation (§6);
- no import of the manual entries of a remote provider yet: they stay skipped
  as `no_file` (`REMOTE-IMPORTS.md`); this shape could hold them later.

## 2. Concepts

| Concept | Meaning |
|---|---|
| Recording | `origin: "import"`: a workout imported from a file, positioned or not |
| Credit row | `origin: "credit"`: someone else's recording credited to the account (`SHARED-ACTIVITIES.md`) |
| Manual entry | `origin: "manual"`: a workout typed in by its owner, no file, no geometry |
| Authored workout | a recording or a manual entry: the owner's own activity (`Workout.authored`, `#authored?`) |

## 3. Persistence

- `workouts_origin` accepts `manual`. `workouts_recording_shape` gives it the
  credit row's branch: no `start_point`, `bounds`, `points_count` or
  `import_format`. `workouts_credit_shape` lets it through with `import` (no
  credit column).
- `workouts_manual_shape` pins what no hand-typed entry carries: no
  `source_digest`, `import_connection_id`, `external_id` or `source`; no
  cadence, maximum power, maximum speed, best pace or grade-adjusted pace; no
  elevation range, filter or DEM request (`elevation_source = 'device'`,
  `recorded_elevation = false`); no weather, places, anomalies or contested
  metrics.
- The figures a manual entry may hold: `started_at`, `duration`,
  `moving_time` (with `pause_time = duration − moving_time`), `distance`,
  `ascent` (`descent` stays 0), `average_heart_rate`, `max_heart_rate`,
  `calories`, `average_power`, and the derived `average_speed` and
  `average_pace`. The text fields, `commute`, the sport and the equipment are
  the recording's.
- `Workout#manual?`, the `manual_entries` and `authored` scopes. `recordings`
  stays `import` only, so every track-assuming read and sweep already leaves a
  manual entry alone; `positioned?` is false.

## 4. Validation

`Workout#manual_figures_are_plausible` (manual entries only), in SI:

| Figure | Bounds |
|---|---|
| `duration`, `moving_time` | 1 s – 7 days, `moving_time ≤ duration` |
| `distance` | 0 – 2 000 km |
| `ascent` | 0 – 20 000 m; positive only for a sport with `records_elevation` |
| heart rates | 20 – 250 bpm, the maximum ≥ the average |
| `calories` | 0 – 20 000 kcal |
| `average_power` | 1 – 3 000 W |
| `started_at` | not in the future (5 minutes' skew allowed) |

Error types: `implausible`, `below_average`, `in_future`, `not_for_sport`,
translated under `activerecord.errors.models.workout`.

## 5. Web

- `Allure::ImportSources::MANUAL` (kind `:manual`, icon `pencil`) is always
  enabled. Its panel (`workout_imports/sources/_manual`) is a form of its own,
  rendered after the upload form, which hides while the tab is selected.
- `ManualWorkoutForm` (ActiveModel) keeps what was typed: the sport, the local
  start (`datetime-local`, read in the account's time zone), the duration and
  moving time as hours / minutes / seconds, the distance in km or mi and the
  ascent in m or ft (a comma or a point as the decimal separator), the
  optional heart rates, calories and power, the text fields, commute and
  equipment. `to_attributes` returns SI or names each unreadable field;
  `adopt_errors` puts the model's refusals under their fields.
- `POST /workouts/manual` (`ManualWorkoutsController#create`) creates the
  entry and redirects to its page; a refusal re-renders the import page with
  the manual tab selected (422).
- The entry's edit page is the workout's (`GET /workouts/:id/edit`), with the
  same form; `PATCH /workouts/:id` routes a manual entry to
  `Workouts::ManualEntry`. Every figure is editable.
- `Workouts::ManualEntry` is the single write seam: it derives the moving time
  (the whole duration unless given, following a changed duration while it was
  the whole of it), the pause time, the average speed and pace; saves; then
  syncs the equipment (`Equipments::Totals`) and emits `workout.created` or
  `workout.updated` with the representation's field names.

## 6. What it counts for

- **Counts:** `user.workouts` reads — the list (cards and table), the hub
  (figures, pulse, calendar, sport mix, regularity), statistics, equipment
  totals, the account export, the REST API, webhooks and MCP.
- **Never counts:** the seven column records (`Records::RecomputeService`
  skips `origin = 'manual'`) and everything derived from a track.
- **Bulk actions** (`[devdoc:bulk-actions]`): selectable
  (`Workouts::BulkSelection` reads `authored`). Commute and equipment apply as
  for a recording; a sport change goes through `Workouts::SportChange`, which
  changes a manual entry's sport alone (no file, no analysis) and fails with
  `ReanalysisFailed` when the new sport refuses a figure (an ascent);
  deletion is the ordinary cascade.
- **Publication:** refused with `no_geometry`, as a positionless recording
  (`NO-GPS.md`). The entry's page offers no publish form.
- **Participations:** `Participations::Propose` and the recording rules accept
  a recording only.

## 7. Presentation

The owner's page is `workouts/manual`: header with « Modifier » and the `⋯`
deletion, the « Saisie manuelle » pill and the commute badge, the summary of
the typed figures (`Workout#metric_visible?` shows an optional figure only
when entered, the distance figures only with a distance, the ascent only when
positive, nothing an analysis derives), the §19.30 scope line, and the
description card. Another account gets a 404. The list card shows the pencil
state where a route image would be, the table a dash for an empty figure.

## 8. REST API and MCP

- `POST /api/rest/v1/workouts` (`write`, idempotent, `API.md`): `sport`,
  `started_at` (ISO 8601 with an offset) and `elapsed_time` required;
  `moving_time`, `distance`, `ascent`, `average_heart_rate`, `max_heart_rate`,
  `calories`, `average_power` (SI, `null` clears an optional one), `title`,
  `description`, `notes`, `commute`, `equipment_ids`. **201** with the
  `Workout` and a `Location`. Type errors are `invalid_type`, a missing field
  `required`, the model's refusals keep their type under the representation's
  names (`elapsed_time` for `duration`).
- `PATCH /workouts/{id}` on a manual entry also takes those figures; on a
  recording they are `not_editable`.
- The representation carries `origin: "manual"`, `positioned: false`,
  `import_format: null`, no `track` or `original` link.
- MCP's workout summary carries the same `origin`.

## 9. Verification

- `spec/services/workouts/manual_entry_spec.rb`: creation, derivation,
  validation, equipment totals, records, webhooks, the database shape, the
  sport change.
- `spec/models/manual_workout_form_spec.rb`: units, time zone, unreadable
  fields, the round trip from a workout.
- `spec/requests/workout_manual_entries_spec.rb`: the panel, creation and its
  refusal, the page, the 404, the edit, the publication refusal, the list.
- `spec/requests/api/rest/v1/workout_writes_spec.rb`: creation, required and
  typed fields, the model's refusals, idempotency, the manual `PATCH`, and the
  `not_editable` refusal on a recording, each against the OpenAPI document.
- The demo seed: a manifest's `manual_workouts` (key, sport, title, local
  `started_at`, the SI figures of §3, text, equipment, commute) go through
  `Workouts::ManualEntry` and are found again by title on a re-run; both
  manifests carry some, and `spec/seeds/` checks them.
