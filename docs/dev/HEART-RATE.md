# Heart-rate contract

Allure stores heart rate and shows it. It interprets it only through the
owner-only analysis this document defines: the profile, the zones, the
histogram, the training load and the zone distribution. Nothing of it leaves
the account.

## 1. Decisions

| # | Decision | Reason |
|---|---|---|
| D1 | Store a **seconds-per-bpm histogram** (191 bins, 30–220 bpm) per workout, never time per zone alone | zones derive at read time; changing a threshold never re-reads a point |
| D2 | Denormalize zone seconds and load on the same row with a **zones fingerprint** | SQL aggregation for statistics and load; a per-account sweep converges, and a stale row is sliced on the fly |
| D3 | The heart-rate profile lives on `users` (maximum, resting, basis, bounds) | four columns need no table; a per-sport override can come later without a contract change |
| D4 | Compute **synchronously** at import and re-analysis (pure before the transaction, persisted inside it), **backfill** from the stored points | the `BestEfforts::Rebuild` pattern; the original is never re-parsed |
| D5 | Generation marker `workouts.heart_rate_version`; a `workout_heart_rates` row exists only when at least one valid beat was recorded | the sweep converges without empty rows |
| D6 | Everything new is **owner-only**: never in a snapshot, a Note, a credit row, a leaderboard, a webhook payload | heart rate is health data |
| D7 | **New** publishing profiles do not share heart rate by default; existing profiles are never changed | a stored choice is never altered silently |
| D8 | Load is **Edwards' TRIMP** (Σ minutes in zone k × k), with **nothing under the load floor** (ten points under the Z2 edge, in the zones' basis: 50 % of the maximum with the default bounds, Edwards' own lower limit) | needs no sex, weight or lactate threshold; matches five zones; Edwards gives no load under 50 % |
| D9 | The hub pulse (`Allure::Stats::Intensity`) does **not** mix heart-rate load in | it would penalize weeks without a strap |
| D10 | A value a losing strap **held** (`hr_frozen`) is not a reading: the histogram skips it like an out-of-range value | skipping a non-reading is not correcting one; the anomaly pass already calls it so |
| D11 | Missing heart rate is **never imputed**: a partial recording's load counts the time that carries a heart rate, and the surfaces say so | an estimate in place of a measurement would be invisible in the load |
| D12 | The load is **Allure's own unit**, and every surface says it compares with neither another application's load nor another person | Edwards points and a stress score differ by about a factor of two for the same hour |

The rejected alternatives are listed in §12.

## 2. The heart-rate profile

An account **has a heart-rate profile** when `users.max_heart_rate` is set.
Without one, Allure interprets nothing: workouts show their recorded values
without interpretation.

| Column | Type | Rule |
|---|---|---|
| `max_heart_rate` | integer, null | `100..220` |
| `resting_heart_rate` | integer, null | `25..120`, below the maximum |
| `heart_rate_zone_basis` | string, `max` | `max` (% of the maximum) or `reserve` (Karvonen: `rest + % × (max − rest)`, requires the resting value) |
| `heart_rate_zone_bounds` | integer[4], `{60,70,80,90}` | lower bounds of Z2…Z5 in percent, strictly increasing, each in `30..99` |

The database checks the ranges, the order of resting and maximum, the basis,
and the array length; the model also checks the strict increase, the bound
range and the resting value a `reserve` basis needs. The owner edits all four
at `/settings/heart-rate`, where a « Rétablir les valeurs par défaut » action
restores `60, 70, 80, 90`.

The page proposes the **observed maximum** (`HeartRates::ObservedMaximum`):
the highest bpm a recording spent at least 10 seconds at or above, read from
its histogram (so a single plausible spike never sets it), over the last 12
months (the whole history when none), skipping sparse recordings and any
workout whose `contested_metrics` names `max_heart_rate`, with a link to the
workout and a one-click « Utiliser cette valeur ». It says the observed value
is a floor of the true maximum, and when it exceeds the stored maximum.

The zone table of the page follows the form as it is typed
(`heart_rate_zones_preview_controller.js`, same rule and rounding as
`Zones`), names each zone with one line of description, and states the load
floor. The basis hint says that equal percentages give higher thresholds
under the reserve. Bounds whose thresholds round to the same bpm are refused
(`indistinct`).

## 3. Zones

`Allure::HeartRate::Zones` turns a profile into five zones. Z1 has no floor:
every reading below the Z2 threshold is Z1; Z5 has no ceiling. Thresholds are
rounded to the whole bpm, so slicing the per-bpm histogram is exact: a bpm
belongs to the highest zone whose threshold it reaches.

Zone names: Récupération / Endurance / Tempo / Seuil / Maximal (Recovery /
Endurance / Tempo / Threshold / Maximum).

The **load floor** is `bounds[0] − 10` percent in the same basis
(`Zones#load_floor`); time under it stays in Z1 and carries no load.

The **fingerprint** is the first 16 hex digits of the SHA-256 of the canonical
JSON `[METHOD_VERSION, basis, max, rest, bounds]` (`rest` null under the `max`
basis, so a resting value never changes `max`-basis zones). Bumping
`Zones::METHOD_VERSION` makes every stored slice stale, so it is read again
from the histogram until the rows are rewritten.

## 4. The histogram

`Allure::HeartRate::Histogram` (pure, versioned) reads recording segments —
the analyzer's in-memory segment metrics or the stored `TrackSegment` rows,
both through the `PointSerializer` keys:

- every point whose `hr` is a reading in `Allure::Gpx::Anomalies::HR_RANGE`
  (30–220) credits `min(next.t − t, 30 s)` to its bpm (a step held to the
  right); the last point of a segment credits nothing; a non-positive interval
  credits nothing;
- a value a losing strap held is not a reading (D10):
  `Allure::HeartRate::FrozenRuns` applies the anomaly pass's `hr_frozen`
  definition per segment (the same value over at least 8 samples and 10 s,
  then at least 5 s without heart rate) and its credit goes to
  `frozen_seconds` instead of a bin;
- `recorded_seconds` = Σ (last.t − first.t) over the segments, pauses inside a
  segment included (a FIT timer stop leaves its resume point in the next
  segment, so a whole pause can sit between two points);
- `covered_seconds` = Σ `min(next.t − t, 30 s)` over every pair of points: the
  time the device recorded, pauses excluded;
- `sampled_seconds` = the credited total; **coverage = sampled / covered**,
  capped at 1 — the share of the recorded time that carries a heart rate,
  whatever the pauses;
- a recording is **sparse** when more than half of its intervals exceed the
  cap (a summary export with a point every few minutes): its readings cannot
  be spread over the time between them;
- bins are whole seconds after the sum is rounded per bin.

Anomalies never correct the histogram: out-of-range readings and frozen
values are skipped, nothing is moved or estimated. A row is **usable** when it
is not sparse and its coverage reaches `MIN_COVERAGE = 0.5`
(`WorkoutHeartRate.usable`); otherwise the row exists but feeds no load and
no statistic, and the zone tab says why (§6). Coverage under
`FULL_COVERAGE = 0.95` is written under the zone bar.

Rows exist for recordings only (`origin: "import"`), positioned or not
(`NO-GPS.md`: an indoor session is where heart rate matters most). Credit
rows, manual entries and received notes never get one.

## 5. Persistence

`workout_heart_rates`:

| Column | Type | Rule |
|---|---|---|
| `workout_id` | bigint | unique, FK cascade |
| `version` | integer | `Histogram::VERSION` |
| `histogram` | integer[191] | seconds per bpm from 30 |
| `sampled_seconds`, `recorded_seconds`, `covered_seconds`, `frozen_seconds` | integer | `>= 0` |
| `sparse` | boolean | default false |
| `zone_seconds` | integer[5], null | seconds in Z1…Z5 under `zones_fingerprint` |
| `load` | numeric(8,1), null | Edwards load above the load floor under `zones_fingerprint` |
| `zones_fingerprint` | string, null | null exactly when `zone_seconds` is |

`workouts.heart_rate_version` (default 0) is the generation marker
(`DERIVATIONS.md`).

- `HeartRates::Rebuild.compute(segments:)` runs before the transaction in
  `Workouts::Importer` and `Workouts::Reanalyzer`; `#persist(result)` runs
  inside it, replaces the row (or deletes it when no beat was recorded),
  slices the zones when the account has a profile, and stamps the marker.
- `HeartRates::BackfillJob` — id cursor, 100 per batch, scope
  `Workout.recordings.where(heart_rate_version < VERSION)`, from the stored
  points; `/admin/jobs` card and audited `heart_rate_backfill_enqueued`;
  `bin/rails workouts:heart_rate` (`AFTER_ID=`).
- `Workouts::UserBackfillJob` kind `heart_rate`, with its counter and button
  on `/settings/data`.
- `HeartRates::RezoneJob(user)` — after the profile changes: every row of the
  account whose fingerprint differs is re-sliced from its histogram in batches
  of 200, without reading a point; clearing the profile nulls the zone
  columns. One per account at a time.
- `WorkoutHeartRate#zone_seconds_for(zones)` slices on the fly when the stored
  fingerprint is stale, so a page is never wrong while the job runs.

## 6. The « Zones » analysis tab

On the owner's workout page, the merged analysis card (`DESIGN.md` §20.3) gains
a « Zones » tab when the recording has a histogram and the account has a
profile. It opens on one line naming the basis and the maximum (and the
resting value under the reserve) with « Modifier mes zones ». A sparse or
partial row (`Result#unusable_reason`) shows only why there are no zones and
that the session counts in no load; a usable row shows:

- a stacked **zone bar** (`DESIGN.md` §10.21) in the five steps of the primary
  ramp (the calendar's), each segment named with its zone, time and share;
- the equivalent table: zone, name, bpm range, time, share;
- « Fréquence cardiaque présente sur N % du temps enregistré (pauses
  exclues) » under 95 %, and the frozen time left out when there is any, with
  a pointer to « Qualité des données » when it holds a heart-rate finding;
- the session's load in points, with the method, the time under the load
  floor, and — under 95 % — that the time without heart rate counts nothing;
- hovering, focusing or pinning a zone row shades every stretch ridden in
  that zone on the profile and the map, like any analysis row: the
  `allure:analysis-highlight` event carries a `ranges` list beside its
  start and end. `Allure::HeartRate::ZoneRanges` places the readings on the
  cumulative distance at render time (no stored column, so a profile change
  never reads a point), joins same-zone stretches closer than 50 m and drops
  those under 20 m — display only, the times still come from the histogram.
  A duration-only session has no stretch to show.

Never on the reader's view (`?as=publication`), a credit row, a manual entry,
or a received note.

## 7. Publishing profiles

- `PublishingProfile::HEALTH_METRIC_KEYS = %w[average_heart_rate max_heart_rate]`;
  `DEFAULT_SETTINGS["metrics"]` excludes them, so a **new** profile shares no
  heart rate until the owner ticks it.
- The form groups the metrics (« Parcours et durée », « Vitesse et allure »,
  « Capteurs ») and states under the heart-rate pair: heart rate is health
  data, shared only when ticked; zones and the maximum never are.
- Existing profiles keep their stored list.
- The snapshot, the Note dialect, the received-note parser and the relay carry
  none of it. Negative specs lock the absence of zones, histogram and load from
  every snapshot and outgoing object.

## 8. API, MCP, export

- `GET /api/rest/v1/workouts/{id}` (detail only, like `weather`):
  `heart_rate: { coverage, sampled_seconds, recorded_seconds, covered_seconds,
  frozen_seconds, load, load_floor_bpm, zones: [{ zone, lower_bpm, upper_bpm,
  seconds }] | null } | null` — null without a usable row, `zones`, `load` and
  `load_floor_bpm` null without a profile; `coverage` is sampled over
  covered. The list form and webhook payloads carry none of it; MCP
  `get_workout_context` inherits the detail.
- `GET /api/rest/v1/me`: `heart_rate_profile: { max, rest, basis, bounds,
  thresholds_bpm } | null`.
- The account export carries the profile under `account.json` →
  `heart_rate_profile`.

## 9. Training load

- `Allure::Stats::TrainingLoad` (pure): daily loads in, per day
  `{date, load, atl, ctl, tsb}` out, with
  `ctl_t = ctl_{t−1} + (load_t − ctl_{t−1}) / 42`, `atl` with 7, and
  `tsb_t = ctl_{t−1} − atl_{t−1}`, starting at 0.
- Daily loads: usable rows of the account's recordings, the day in
  `users.time_zone`, `SUM(load)`.
- A hub card « Charge d'entraînement »: Condition, Fatigue, Forme, a short ⓘ
  (method, own unit), a 90-day ECharts chart through `lib/charts/`
  ([CHARTS.md](CHARTS.md)), the count of sessions without heart rate and of
  sessions with partial heart rate (D11), « Comment lire ces chiffres » (load
  and floor, the three figures and the sign of the form, the unit compared
  with nothing else, nothing imputed, the warm-up), and the equivalent table.
  Shown once one usable row exists; without a profile, an empty state pointing
  to `/settings/heart-rate`.
- **Warm-up**: both averages start at zero on the first usable day, so the
  first 42 days of the history are shaded on the chart when they fall in the
  window, with a sentence; fitness reaches 64 % of a steady load after 42 days.
- The **weekly table** groups the days by the account's calendar week
  (`users.week_start`), « Semaine du … », the figures of the week's last day
  and its summed load; the unfinished current week and a week the window cuts
  are marked.

## 10. Zone distribution

`/me/stats/heart_rate` (`StatsController#heart_rate`, linked from the stats
hub and the load card): an introduction naming the basis with « Modifier mes
zones », zone distribution per week (last 26) or month (last 24) in hours or
in shares of each period (`scale=share`), stacked bars on the zone ramp with
every period of the window kept, sport filter, a three-intensity reading of
the window (low Z1–Z2, moderate Z3, high Z4–Z5) presented as a landmark, not
a prescription, and the table of the periods holding heart rate.

`HeartRates::History` reads both from the usable rows of the account's
recordings; a row whose fingerprint is stale is sliced from its histogram, so
the totals never mix two zone definitions.

## 11. Privacy negatives

- No zone, threshold, histogram, coverage, load or profile value enters a
  `WorkoutPublication` snapshot, a retained representation, an outgoing Note,
  a `RemoteNote`, a comment, a reaction, a credit row, a webhook payload, a
  push payload, or a leaderboard.
- The only heart-rate values a publication may carry are
  `average_heart_rate` and `max_heart_rate`, and only when the profile ticks
  them.

## 12. Out of scope

- **Per-sport-family profile**: an override per sport family (maximum,
  resting value, basis, bounds) and an optional threshold basis. The account
  profile stays the default.
- **Aerobic progression**: cardiac cost on repeated courses, efficiency
  factor, aerobic decoupling.
- **Estimated VO2max and heart-rate calories**: crude formulas needing age,
  weight and sex.
- Heart rate on boards or on the wire beyond the two summary metrics a
  profile may already share.
- Zone-driven detected intervals.
