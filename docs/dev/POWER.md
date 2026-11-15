# Power contract

Power-duration efforts, power records and their publication. This document
specifies the power-duration efforts shown on the workout page and
`/me/records`, the power records derived from them, the virtual-sport
exclusions, the shared-profile projection, the publication markers, the API,
the MCP and the webhook. It does not change the summary tiles, the map
gradient, the analysis tables, the seven workout-column records, or the classic
`Record` types.

## 1. Settled choices

| # | Question | Answer |
|---|---|---|
| Q1 | Which durations? | Five standard durations: 5 s, 1 min, 5 min, 20 min, 60 min. |
| Q2 | Rowing? | Enable `sports.records_power` for `rowing` and `rowing_virtual`. No power intervals result: the `swim` colour group has no power profile (`Allure::Laps::Profiles`). |
| Q3 | Virtual distance efforts? | Stop computing them for a power-led sport and delete the existing rows. Keep `FD` (farthest distance) and the elevation records. |
| Q4 | Power spikes? | An implausible reading holds 0 W: at least 2 500 W, or an isolated burst of at most two readings each at least 1 000 W and at least 4× the readings immediately before and after it. |
| Q5 | Webhook? | Extend `record.achieved` with a `kind` discriminator and, for power, `duration_key`, `duration`, `average_power`. The record backfills announce nothing. |
| Q6 | Shared profile? | Include power records in the existing records block; update the hint in five languages, and the privacy copy wherever it enumerates the shared figures. |
| Q7 | Hub? | One power line per workout, the longest duration it holds. |

## 2. Decisions

| # | Decision | Reason |
|---|---|---|
| D1 | The curve is five **standard durations** — 5 s, 1 min, 5 min, 20 min, 60 min — one persisted row per `(workout, duration)` | the cycling convention; five rows fit a table and a marker list |
| D2 | A window is the **time-weighted mean** of the readings it covers; each reading holds until the **next point**; the last point of a run holds nothing | the heart-rate histogram's rule (`Allure::HeartRate::Histogram`); a smart recording must not weight one sample more than another |
| D3 | A point **without a reading holds 0 W**; a run ends at a recording-segment boundary, at an interval over 30 s, and after 30 s without a reading | a dropout can only lower a mean; a pause is not effort |
| D4 | **Zeros count**: coasting is part of the mean | the standard convention in cycling power analysis; dropping zeros would reward freewheeling |
| D5 | A candidate window starts **or ends** on a recorded point; two two-pointer passes over the cumulative energy, O(n) per duration; ties break on the earlier start, then the earlier reading | the mean is piecewise linear with breakpoints at both ends; the start-only claim is false (§3.2) |
| D6 | Each duration caps the interval it may hold: `s5` 2 s, `min1` 10 s, `min5`/`min20`/`min60` 30 s | a smart recording's single held reading must not become a 5 s record |
| D7 | An **implausible reading holds 0 W** (§3.1), computed from the points, never from the stored findings | the anomaly pass flags real sprints too; findings are merged, rounded and capped at 100 per kind |
| D8 | Two tables — `power_efforts` and `power_records` — mirroring `best_efforts` and `effort_records` | the same shape, the same recompute, the same delete rules |
| D9 | Computed at import and re-analysis (pure before the transaction, persisted inside it), backfilled from the stored points, with `workouts.power_efforts_version`; **no analyzer version bump** | the `BestEfforts::Rebuild`/`HeartRates::Rebuild` pattern; the original is never re-parsed |
| D10 | `sports.records_power` gates the feature; rowing and rowing_virtual are enabled | the flag already gates power intervals; an erg measures power |
| D11 | A **power-led virtual sport** (`Sport#power_led?`) hides `AS`/`MS`, stops computing its distance efforts, and the existing distance efforts/records are deleted; `FD` and the elevation records stay | the platform's speed is a game output; distance is a volume record |
| D12 | A publication carries **duration markers only**, under the `records` setting and only when `average_power` is shared | the marker contract and the profile's promise (§7.4) |
| D13 | `record.achieved` gains a `kind` discriminator and, for power, `duration_key`, `duration`, `average_power`; the record backfills announce nothing | additive fields; no storm from a sweep |
| D14 | The shared profile includes power records in its records block; the hint is updated in five languages, and the privacy copy is amended wherever it enumerates the shared figures | the owner opted into sharing records; the copy must say what is shared |
| D15 | Labels are qualified (« Puissance 5 min » / "Power 5 min"); the glossary gains the term in five languages; the medal tooltips name power | a bare "5 min" is ambiguous beside "10 km"; "meilleur temps" is wrong for watts |
| D16 | The hub shows **one power line per workout**, the longest duration it holds | one ride can hold five; the card shows three |
| D17 | Credit rows and manual entries never hold power efforts | a credit row's points are the source's; a manual entry has no points |
| D18 | An all-zero power stream yields no effort | a trainer with no meter writes 0 W; a 0 W mean is not a record |
| D19 | The pure library is `Allure::Power::Efforts`; the services are `PowerEfforts::Rebuild` and `PowerEfforts::BackfillJob` | FTP, zones and normalized power will follow in the same namespace |
| D20 | Power efforts are **owner-only**; the curve never enters a snapshot or a Note; only the duration markers travel | the established record boundary |

Rejected: a "best average power of the workout" record (it rewards short
rides), a "max power" record (one sample, spike-prone), any watts-per-kilo
figure until the account stores a body weight, which is health data, running
power until a contract, moving-time windows, windows that bridge a pause, a
power-duration chart, and notifications or emails for a new power record.

## 3. Semantics

- A power effort is the **highest time-weighted mean power over a standard
  duration** inside one workout.
- The reading at point `i` holds from `t_i` to `t_(i+1)`; the last point of a
  run holds nothing. A point without a reading, or with an implausible one
  (§3.1), holds 0 W.
- A run is one recording segment (`track_segments` boundary), split at an
  interval over 30 s and after 30 s without a reading. No window crosses a
  split. For a duration `D`, the run is further split at an interval over its
  `max_interval` (§4).
- A window is exactly `D` seconds. It starts or ends on a recorded point; the
  other boundary is interpolated linearly inside the interval that reaches
  `D`. The mean is the window's energy divided by `D`.
- A duration no run can cover yields no effort. A workout without a power
  reading yields none. A best mean of 0 W is not stored (D18).
- The stored power is rounded to the nearest watt, the display resolution used
  everywhere else.
- `started_at` is the window's start. `start_offset_meters` /
  `end_offset_meters` are the cumulative distance at the boundaries, linearly
  interpolated; both are **nil when the workout records no distance** (a
  duration-only session). The row then highlights by elapsed time, derived
  from `started_at` and `duration_seconds`.
- **Nothing is imputed.** A workout with a partial power recording gets the
  windows its readings cover and no others; the surfaces say nothing about the
  rest.
- The summary tile's average power is the **sample mean** (zeros included);
  the curve is **time-weighted**. On a 1 Hz recording they agree; on a smart
  recording they can differ. The tile is not changed.

### 3.1 Implausible readings

- A reading of at least **2 500 W** is implausible.
- A maximal burst of at most **two consecutive readings**, each at least
  **1 000 W**, is implausible when the nearest reading before and the nearest
  reading after the burst, when they exist, are each at most a quarter of the
  burst's smallest reading.
- An implausible reading holds 0 W; it is not corrected, and the anomaly pass
  is not consulted. The stored findings are merged over 10 s, rounded to the
  second and capped at 100 per kind, so they cannot exclude a precise window.
  The anomaly pass's `power_spike` rule (`≥ 2 500 W`, or `≥ 1 000 W` and `4 ×`
  the median of ±15 points) flags real sprints as well; that is a separate
  data-quality defect, out of scope here.

### 3.2 Why both ends

100 W at 0 s, 200 W at 3 s, 0 W at 6 s, run to 20 s, `D = 5 s`:

- start-anchored, 0–5 s: `(100 × 3 + 200 × 2) / 5 = 140 W`;
- end-anchored, 1–6 s: `(100 × 2 + 200 × 3) / 5 = 160 W`.

The optimum starts inside an interval. Checking only starts on recorded points
loses 20 W; at 1 Hz the two passes coincide, which is why the error is
invisible on dense files and real on smart recordings.

## 4. Durations

Keys avoid the metre collision of the distance table (`m400` is 400 m):
`min1` is one minute, not one metre.

| Key | Seconds | `max_interval` | Label (FR / EN) |
|---|---|---|---|
| `s5` | 5 | 2 s | 5 s |
| `min1` | 60 | 10 s | 1 min |
| `min5` | 300 | 30 s | 5 min |
| `min20` | 1 200 | 30 s | 20 min |
| `min60` | 3 600 | 30 s | 60 min |

`Allure::Power::Efforts::DURATIONS` holds the frozen ordered table, each row
carrying its key, seconds and `max_interval`; `VERSION = 1` stamps
`workouts.power_efforts_version`. A duration is a code change plus five locale
labels plus a backfill run, exactly like a best-effort distance. The bare
duration is `records.power_durations.<key>`; the qualified label used beside
distances is `records.power.<key>` (« Puissance 5 min » / "Power 5 min").

## 5. Data model

### 5.1 `power_efforts`

| Column | Type | Meaning |
|---|---|---|
| `id` | bigint | primary key |
| `user_id` | bigint | not null, `ON DELETE CASCADE` |
| `sport_id` | bigint | not null, FK `sports` |
| `workout_id` | bigint | not null, `ON DELETE CASCADE` |
| `duration_key` | string | not null, `s5` … `min60` |
| `duration_seconds` | integer | not null, the window length |
| `average_power` | integer | not null, watts, strictly positive |
| `started_at` | datetime | not null, the window's start |
| `start_offset_meters` | decimal(14,3) | cumulative workout distance at the start, nullable |
| `end_offset_meters` | decimal(14,3) | cumulative workout distance at the end, nullable |
| timestamps | datetime | Rails audit columns |

Unique `(workout_id, duration_key)`; index
`(user_id, sport_id, duration_key, average_power)`. Checks:
`duration_seconds > 0`, `average_power > 0`, offsets non-negative, and
`end_offset_meters >= start_offset_meters` when both are present. Rows are
display-only: never URL-addressable, never federated, cascaded with their
workout.

### 5.2 `power_records`

| Column | Type | Meaning |
|---|---|---|
| `id` | bigint | primary key |
| `user_id` | bigint | not null, `ON DELETE CASCADE` |
| `sport_id` | bigint | not null, FK `sports` |
| `workout_id` | bigint | nullable, `ON DELETE SET NULL` |
| `duration_key` | string | not null |
| `duration_seconds` | integer | not null |
| `average_power` | integer | not null |
| `workout_started_at` | datetime | not null, denormalized for display |
| timestamps | datetime | Rails audit columns |

Unique `(user_id, sport_id, duration_key)`; index `(workout_id)`. Checks:
`duration_seconds > 0`, `average_power > 0`. The `workout_id` FK is not
cascade: deleting the winning workout nullifies the row and the recompute
re-points it to the runner-up (or removes it), mirroring `effort_records`.
`Workout` gains `has_many :power_efforts, dependent: :destroy` and
`has_many :power_records, dependent: :nullify`; `User` gains the destroy
associations; `Sport` gains `dependent: :restrict_with_exception`, as for
`effort_records`.

## 6. Computation and recompute

### 6.1 The pure library

`Allure::Power::Efforts.find(segments:, durations:, workout_started_at:)` runs
on `Allure::Segments::PointStream` and returns one `Effort` per covered
duration, in the requested order:

- build the runs: one recording segment, split where the interval between
  consecutive points exceeds 30 s or where the gap since the last reading
  exceeds 30 s; then, per duration, split further at intervals over its
  `max_interval`;
- build the cumulative energy per run: each point's reading (0 W when missing
  or implausible) holds for the interval to the next point; the last point
  holds nothing;
- for each duration, run two two-pointer passes over each run: **start
  anchored** (`s = t_i`, end interpolated) and **end anchored**
  (`end = t_j`, start interpolated); the window energy is
  `E(end) − E(start)`, the mean is that energy over `D`;
- keep the best mean per duration; ties break on the earlier start, then the
  earlier reading; a mean of 0 W is not stored.

`Effort` carries `duration_key`, `duration_seconds`, `average_power`,
`started_at`, `start_offset_meters`, `end_offset_meters`. The offsets are
interpolated from the cumulative distance; `PowerEfforts::Rebuild.persist`
stores them as nil when the workout records no distance.

### 6.2 Rebuild and records

- `PowerEfforts::Rebuild.compute` is pure and runs before the caller's
  transaction; `persist` replaces the workout's rows inside it and stamps
  `workouts.power_efforts_version`. It is called by `Workouts::Importer` and
  `Workouts::Reanalyzer` beside `BestEfforts::Rebuild`, with the same
  `context` metric pattern (`allure_power_efforts_rebuild_duration_seconds`).
- `Records::RecomputeService` gains `recompute_power_records`: for each
  duration the sport records, the winner is the highest `average_power` among
  the athlete's `power_efforts`, tie on the earlier start, then the earlier
  row. A holder change emits `record.achieved` (D13). The service gains
  `announce:` (default true); the dedicated record backfills pass
  `announce: false`.
- Deleting a workout cascades its `power_efforts`; its `power_records` row is
  nullified and the destroy callback recomputes the runner-up, exactly as for
  `effort_records`.
- A re-analysis that changes the curve without changing a record-source
  column enqueues the `(user, sport)` recompute after commit, as `MC` does; the
  existing `Segments::MatchWorkoutJob` and `Laps::RebuildJob` already do it.
- A credit row has no power column and its points are the source's, so it
  never holds a power effort; a manual entry has no points at all.

### 6.3 Virtual sports and cleanup

For a power-led sport (`Sport#power_led?`, `cycling_virtual` today):

- `PowerEfforts::Rebuild.compute` returns the curve; the sport's
  `records_power` is true.
- `BestEfforts::Rebuild.compute` returns `[]`; the existing rows are deleted
  by the best-efforts backfill (or any re-analysis), because the ride profile
  still lists `cycling_virtual` and `persist([])` replaces the rows.
- `Records::RecomputeService` deletes the sport's distance records: each
  profile key has no winner, so its `EffortRecord` is removed. It also deletes
  an `EffortRecord` whose key is no longer in the sport's profile, as a safety
  net.
- `Record.visible_type?` hides `AS` and `MS` when `sport.power_led?`; the
  recompute does not compute those two types for a power-led sport and deletes
  any existing row, so no read path (web, REST, MCP, webhook) can see them.
- `FD`, `HA` and `MC` stay: distance and elevation are volume records, not
  speed-quality records. The other display-only types (`AP`/`BP` on a speed
  sport) keep today's behaviour; that existing deviation is out of scope.

`running_virtual` is untouched: a treadmill sets the distance, not a game
engine. Rowing keeps its distance efforts and gains the power curve; it gets no
power intervals because `Allure::Laps::Profiles` has no `swim` power profile.

### 6.4 Credit rows and manual entries

`PowerEfforts::Rebuild#call` returns unless `@workout.recording?`; the backfill
scope is `Workout.recordings`. A credit row's `track_workout` points carry the
source rider's power, so a copy of `BestEfforts::Rebuild` would credit the
participant with the owner's watts; the guard is explicit. A manual entry has
no points and no curve, even when its typed figures include an average power.

## 7. UI

### 7.1 Workout page

- The Analysis card's « Meilleurs efforts » tab gains a **« Puissance »**
  section before the distance section: duration, watts, personal-place trophy.
  Each row highlights its window on the elevation chart and the map while
  hovered, focused or pinned, like a best effort. For a power-led ride only the
  power section renders; for a workout with both, the two sections share the
  tab.
- The row carries the distance offsets when the workout has a distance; for a
  duration-only session it carries the elapsed range instead, and the chart's
  time axis highlights it. `analysis_row_attributes` gains optional
  `start_elapsed`/`end_elapsed`; `workout_tabs_controller` and
  `elevation_chart_controller` choose the pair matching the axis.
- The tab draws no persistent boundaries: with several overlapping windows
  they would clutter the chart, so the range only appears while a row is
  active.

### 7.2 `/me/records`

Each sport card gains a **« Puissance »** table (duration, watts, set-on date,
linked to the workout) after the classic and distance tables. The card shows
the three panels side by side from `lg` up when all three exist, and stacks
them in that order below; a sport with no power records shows the existing
layout. A card renders when any of the three has a visible row. The page
controller loads `@power_records_by_sport` and orders each sport's rows by
`DURATIONS`.

### 7.3 Hub

« Derniers records » includes power records, newest workout first, with **one
line per workout**: the longest duration the workout holds, its watts, and the
qualified label. A workout holding five power records therefore adds one line,
not five; the workout page shows the full curve. `MeController#latest_records`
groups the power records by workout before merging them with the classic and
distance rows under `RECORD_LIMIT`.

### 7.4 Badge, labels and glossary

- `held_record_labels` gains the workout's power records and
  `snapshot_record_labels` gains `record_durations`; both use the qualified
  label. The badge still names every visible record of the workout, classic
  types, distances and durations together.
- The feed card, the remote note page and the workout page pass the third
  marker list.
- `records.power_durations.<key>` holds the bare duration for the table;
  `records.power.<key>` holds the qualified label for the badge, the hub, the
  shared profile, the feed and the remote note.
- `MedalsHelper#personal_place_*` gains a power family:
  `medals.personal_place.power_second` (« 2e meilleure puissance : %{record} »)
  and `power_third`; the existing `second`/`third` (« 2e meilleur temps ») stay
  for distances and segments.
- `DESIGN.md` §4 gains the glossary entry in five languages (FR « meilleure
  puissance », EN "best power"; DE, ES and NL follow the §4 glossary), §10.4
  gains the power tooltip wording, §20.3 the tab section, §20.8 the third
  panel, and §19.38 the shared-profile copy.
- The publishing profile's `records_hint` says the power markers follow the
  shared `average_power` metric; the shared-profile hint says the records block
  now includes best powers over standard durations.

### 7.5 Personal places

`PowerEfforts::PersonalPlaces` ranks the owner's own efforts per
`(sport, duration)` — gold for the record, silver and bronze for the second and
third best power — derived on read, owner-only, never published. The order
mirrors `Records::RecomputeService`: `average_power` descending, then the
earlier start, then the earlier row, so place 1 is the effort its `PowerRecord`
points at.

### 7.6 Shared profile

`Profiles::SharedRecords` gains a `power_records` group, loaded with only
`id`, `sport_id`, `duration_key`, `average_power` (no source workout, no date,
no link), ordered by `DURATIONS`. The profile card adds a « Puissance »
sub-table under the classic and distance rows. The block is served only when
`users.profile_records_audience` allows the viewer, exactly as today. The hint
is updated in five languages; the §19.38 privacy copy is reviewed and amended
only where it enumerates the shared figures (D14).

### 7.7 Export

`records.json` gains `power_efforts` (per workout, with its window) and
`power_records` (per sport, with its duration and watts), mirroring
`best_efforts` and `effort_records`. No other export file changes.

## 8. Publication and federation

- The snapshot gains **`record_durations`**, an array of the duration keys the
  workout holds, ordered by `DURATIONS`, capped at `MAX_RECORD_MARKERS` (32).
  It is emitted only when the profile's `records` setting is on **and** the
  profile shares `average_power`; it carries no value.
- `WorkoutPublication` adds the key to its allowed representation keys and
  validates the tokens against `Allure::Power::Efforts::DURATIONS.keys`.
- `Federation::Serializers::WorkoutNote` emits a third marker tag beside
  `record_types` and `record_distances`; `Federation::Parsers::RemoteNote`
  parses it with the same allowlist, bounded by `MAX_RECORDS` (32) and
  `MAX_RECORD_CONTENT` (512). Unknown or oversized tokens are skipped with a
  warning; an older peer preserves the unknown tag in `raw` and ignores it, so
  the order of deployment does not matter.
- `RemoteNote` adds the key to its representation allowlist and validation;
  `Federation::Inbox::Create` carries it into the stored representation;
  `Federation::RemoteNoteView`, `Workouts::PublicationView`, the feed card and
  the remote note page render the labels.
- `docs/openapi/v1.yaml` gains the field in the remote-note schema; the
  federation contract (`[devdoc:federation]`) gains the tag row and its rules.
- `dip fed_test` fabricates a `min5` power effort and record on the ring
  workout (as it already fabricates the `mi5` best effort) and asserts the tag
  and its remote parse. The public profile shares `average_power` by default.
- The snapshot is immutable: a later record change stays invisible until the
  owner republishes.

## 9. API and MCP

- `GET /api/rest/v1/records` gains `power_records` (sport, duration key,
  duration in seconds, watts, workout id, achieved at). The existing
  `records` and `best_efforts` arrays keep their shape.
- `GET /api/rest/v1/workouts/{id}/power_efforts` returns the workout's curve
  with its personal place: `duration_key`, `duration`, `average_power`,
  `started_at`, `start_distance`, `end_distance`, `sport`, `personal_place`.
  The route and the OpenAPI document change together; the route/document guard
  spec covers the new operation.
- `get_workout_context` (MCP) gains `power_efforts` under `include_efforts`,
  and `records_set` gains `power_records`. The tool description and the server
  instructions name power-duration bests.
- `docs/openapi/v1.yaml` gains `PowerEffort`, `PowerRecord`, the `Records`
  field and the `RecordAchievedData` fields; the distance examples are fixed
  from `5k`/`10k` to `km5`/`km10`. The contract specs follow.

## 10. Webhooks

`record.achieved` gains a `kind` discriminator (`classic`, `distance`,
`power`) for every variant. A power record carries `duration_key`, `duration`
(seconds) and `average_power` (watts), and its idempotency key is
`record.achieved:<sport>:power:<duration_key>:<workout_uuid>:<average_power>`.
The classic and distance variants keep their existing key shape.

`Records::RecomputeService` gains `announce:` (default true). The dedicated
record backfills — `BestEfforts::BackfillJob`, `PowerEfforts::BackfillJob` and
`Laps::BackfillJob` — pass `announce: false`, so a sweep never announces years
of old outings for any of the three families. A re-analysis of one workout
keeps announcing, as today. The API contract (`[devdoc:api]`) is updated.

## 11. Backfill, operations and metrics

- `workouts.power_efforts_version` (integer, default 0, not null) is stamped
  by `PowerEfforts::Rebuild#persist`; `Allure::Power::Efforts::VERSION` is the
  current generation. The marker covers every recording, as
  `heart_rate_version` does, so a later catalog change converges without a
  special case.
- `PowerEfforts::BackfillJob` (BATCH_SIZE 100, resumable with `after_id`,
  narrowable with `sport_slug`) rebuilds the curve for every recording whose
  marker is older, from the stored points, and recomputes the affected
  `(user, sport)` pairs per batch with `announce: false`. The rebuild returns
  `[]` and deletes the rows for a sport that does not record power.
- `bin/rails power_efforts:backfill` enqueues it (`AFTER_ID` resumes,
  `SPORT=<slug>` narrows), `bin/rails power_efforts:rebuild WORKOUT=<id>`
  rebuilds one workout now. `docs/site/reference/cli.md` gains both rows.
- The audited action `power_efforts_backfill_enqueued` is added to
  `AdminEvent::ACTIONS`; `/admin/jobs` shows the pending count and the action,
  with the flash and confirm copy in five languages.
- The account's own sweep is a `power_efforts` kind on `/settings/data`
  (`Workouts::UserBackfillJob::KINDS`, `pending_scope`, `dispatch`, counts and
  locale labels); it rebuilds inline from the stored points.
- `allure_power_efforts_rebuild_duration_seconds{phase,context}` is declared in
  `Metrics::Schema` and mapped in `Metrics::Catalog` (admin: nil), with the
  metrics contract (`[devdoc:metrics]`) updated; the catalog guard spec fails
  otherwise.
- The release runs `best_efforts:backfill` once for the power-led cleanup and
  `power_efforts:backfill` once for the curve. The release note says that the
  distance efforts of virtual rides disappear from `/me/records` and that
  existing publications keep their frozen markers.

## 12. Testing

- Pure `Allure::Power::Efforts`: the end-anchored counterexample (§3.2),
  exact window, coasting zeros, a missing reading as 0 W, a gap over 30 s, a
  pause between segments, `max_interval` per duration, the spike burst, the
  2 500 W ceiling, a duration longer than the recording, a duration-only
  session (nil offsets, elapsed range), an all-zero stream, the tie-break.
- Models and services: rebuild idempotency, marker stamp, recompute winner and
  tie-break, delete and runner-up, credit rows excluded, manual entries
  excluded, the power-led cleanup (`best_efforts` and `effort_records` gone,
  `AS`/`MS` gone, `FD`/`HA`/`MC` kept), the silent backfills (no webhook), the
  shared profile, the hub's one line per workout.
- Requests: the analysis tab (both sections, power-only, duration-only
  highlight), `/me/records`, the hub, the badge, the shared profile, the
  export.
- API: `/records` with `power_records`, `/workouts/{id}/power_efforts`, the
  OpenAPI contract, the route/document guard, the MCP.
- Federation: the marker tag, the remote parser (known tag, unknown token,
  unknown tag from an older peer), `dip fed_test`.
- Webhooks: the `kind` discriminator, the power payload, the dedupe key, the
  silence of the three record backfills.
- Browser: the tab's hover range on both axes, the records page, the badge,
  the hub.
- Locales: five languages, the completeness spec.
- Metrics: the catalog guard.
- Corpus: run the FIT corpus through the pure library to calibrate the burst
  rule and the `max_interval` table, and report how many windows the rule
  removes.

## 13. Out of scope

- Statistics and totals in kJ, and the sport-mix or radar reading power.
- FTP, power zones, training load, W/kg (needs a stored body weight, which is
  health data).
- A power-duration chart (the table is the contract for now).
- Notifications or emails for a new power record.
- Moving-time windows, and windows that bridge a pause.
- Running power until a contract.
- A "best average power of the workout" or "max power" record.
- The existing display-only `AP`/`BP` rows of a speed sport on the REST and
  webhook paths; this contract only removes `AS`/`MS` for a power-led sport.
