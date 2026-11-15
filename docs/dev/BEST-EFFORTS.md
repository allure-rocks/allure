# Best efforts contract

Standard-distance best efforts shown on `/me/records` and the workout page, the
`MC` (biggest climb) record, and the recompute rules. It does not change the
seven workout-column records, publications or federation.

## 1. Semantics

- A best effort is the fastest time to cover a standard distance inside one
  workout. It is measured as **elapsed time, stops included**.
- An effort lives inside a **single recording segment** (`track_segments`): a
  recording pause is never bridged, matching the effort and split rules.
- Boundaries are interpolated linearly between recorded points to the exact
  distance. Because the elapsed-time function is piecewise linear in the start
  distance, both start-anchored and end-anchored windows are checked; the result
  is exact for the recorded point stream.
- Only the best window per `(workout, distance_key)` is persisted. Ties break on
  the earlier start, then the earlier recorded window.
- Sub-second interpolation is rounded to the nearest integer second, the display
  resolution used everywhere else.
- A distance no single segment can cover yields no effort. GPS elevation is
  irrelevant here; only distance and time are used. The stored cumulative
  distance comes from the cleaned track (`WORKOUT.md` §6.1 and §6.9):
  implausible positions are removed and the vertical term reads the filtered
  elevation, so an analyzer version bump recomputes efforts through
  `Workouts::BackfillRebuildJob` as well as the dedicated backfill below.

## 2. Distance profiles

Distances are metric definitions stored as `distance_meters`; labels are
localized and never converted for the viewer. `Allure::Gpx::BestEfforts` holds
the frozen tables.

| Profile | Key | Metres | Label (FR / EN) |
|---|---|---|---|
| run | `m400` | 400 | 400 m |
| run | `half_mile` | 804.672 | 1/2 mile |
| run | `km1` | 1 000 | 1 km |
| run | `mi1` | 1 609.344 | 1 mile |
| run | `mi2` | 3 218.688 | 2 miles |
| run | `km5` | 5 000 | 5 km |
| run | `km10` | 10 000 | 10 km |
| run | `km15` | 15 000 | 15 km |
| run | `mi10` | 16 093.44 | 10 miles |
| run | `km20` | 20 000 | 20 km |
| run | `half_marathon` | 21 097.5 | Semi-marathon / Half marathon |
| run | `km30` | 30 000 | 30 km |
| run | `marathon` | 42 195 | Marathon |
| ride | `mi5` | 8 046.72 | 5 miles |
| ride | `km10` | 10 000 | 10 km |
| ride | `mi10` | 16 093.44 | 10 miles |
| ride | `km20` | 20 000 | 20 km |
| ride | `km30` | 30 000 | 30 km |
| ride | `km40` | 40 000 | 40 km |
| ride | `km50` | 50 000 | 50 km |
| ride | `km80` | 80 000 | 80 km |
| ride | `mi50` | 80 467.2 | 50 miles |
| row | `m500` | 500 | 500 m |
| row | `km1` | 1 000 | 1 km |
| row | `km2` | 2 000 | 2 km |
| row | `km5` | 5 000 | 5 km |
| row | `km6` | 6 000 | 6 km |
| row | `km10` | 10 000 | 10 km |
| row | `half_marathon` | 21 097.5 | Semi-marathon / Half marathon |
| row | `marathon` | 42 195 | Marathon |

Profile mapping: `run` → running, running_virtual, trail; `ride` → cycling,
cycling_road, cycling_gravel, cycling_electric, cycling_virtual,
cycling_trekking, mountain_biking, mountain_biking_electric, halfbike; `row` →
rowing, rowing_virtual (the Concept2 standard set). Every other sport has no
effort profile. The tables are code constants; extending a profile is a code
change plus locales.

## 3. Data model

### 3.1 `best_efforts`

| Column | Type | Meaning |
|---|---|---|
| `id` | bigint | primary key |
| `user_id` | bigint | not null, `ON DELETE CASCADE` |
| `sport_id` | bigint | not null, FK `sports` |
| `workout_id` | bigint | not null, `ON DELETE CASCADE` |
| `distance_key` | string | not null, profile key |
| `distance_meters` | decimal(14,3) | not null, canonical SI distance |
| `duration_seconds` | integer | not null, elapsed seconds |
| `started_at` | datetime | not null, interpolated effort start |
| `start_offset_meters` | decimal(14,3) | cumulative workout distance at the start |
| `end_offset_meters` | decimal(14,3) | cumulative workout distance at the end |
| timestamps | datetime | Rails audit columns |

Unique `(workout_id, distance_key)`; index
`(user_id, sport_id, distance_key, duration_seconds)`. Checks:
`distance_meters > 0`, `duration_seconds > 0`, offsets non-negative, and
`end_offset_meters >= start_offset_meters`. Rows are display-only: never
URL-addressable, never federated, cascaded with their workout.

### 3.2 `effort_records`

| Column | Type | Meaning |
|---|---|---|
| `id` | bigint | primary key |
| `user_id` | bigint | not null, `ON DELETE CASCADE` |
| `sport_id` | bigint | not null, FK `sports` |
| `workout_id` | bigint | nullable, `ON DELETE SET NULL` |
| `distance_key` | string | not null |
| `distance_meters` | decimal(14,3) | not null |
| `duration_seconds` | integer | not null |
| `workout_started_at` | datetime | not null, denormalized for display |
| timestamps | datetime | Rails audit columns |

Unique `(user_id, sport_id, distance_key)`; index `(workout_id)`. The
`workout_id` FK is not cascade: deleting the winning workout nullifies the row
and the recompute re-points it to the runner-up (or removes it), so a record
survives its source workout, mirroring `records`.

### 3.3 `MC` (biggest climb)

`MC` joins `Record`'s types. The winner is the workout holding the largest
detected climb (`detected_laps.source = "climb"`), and the value is that
climb's `ascent` in metres. Read-time display filtering hides it when
`sport.records_elevation` is false, like `HA`.

## 4. Computation and recompute

- `Allure::Gpx::BestEfforts.find(segments:, distances:, workout_started_at:)`
  is pure Ruby over `Allure::Segments::PointStream` and returns one `Effort`
  per covered distance in profile order.
- `BestEfforts::Rebuild` replaces a workout's `best_efforts` from its stored
  track points. Its pure `compute` step (`Rebuild.compute`) runs before the
  caller's transaction, over the analyzer's in-memory segments or the stored
  track, while `persist` stays inside the import and reanalysis transactions.
  A workout's efforts are therefore committed with the workout and current
  before its `after_commit` records recompute, and the `users` row lock taken
  by the workout insert never covers the CPU scan.
- `Records::RecomputeService` (one call per `(user, sport)`) now also:
  - upserts one `effort_records` row per profile distance from the user's
    `best_efforts` (fastest duration; tie on the earlier start, then row);
  - upserts or removes `MC` from the detected climbs.
- Delete: `best_efforts` cascade with the workout; `effort_records.workout_id`
  nullifies, and the workout's destroy callback recomputes the runner-up.
  `Record`'s existing create/update/destroy callbacks already cover the other
  types and `MC`.

The existing `effort_records` winners may also be projected as labels and
durations on the local member profile when its owner explicitly enables
`users.profile_records_audience` (`none` by default, accepted local followers or
all instance members when shared; `[devdoc:tracking-depth]`). That projection
includes the whole personal history but never its source workout, achievement
date, title, identifier, route or link. It does not make an effort
URL-addressable or federated and does not change winner computation or
publication markers.

- Detected climbs are rebuilt asynchronously, so `Segments::MatchWorkoutJob`
  recomputes records once the laps are fresh, and `Laps::BackfillJob`
  recomputes the affected `(user, sport)` pairs at the end of each batch.

## 5. UI

- `/me/records` (`/records` redirects there): each sport card shows the classic
  records table, then a **Meilleurs efforts / Best efforts** table (distance,
  time, set-on date, linked to the workout) ordered by profile distance. A
  sport card renders when either set has a visible row. Owner-only. The hub's
  « Derniers records » card lists classic and best-effort records together,
  newest workout first.
- Workout page (owner): the merged Analysis card gains a **Meilleurs efforts**
  tab (`ti-stopwatch`) listing the workout's own efforts (distance, time,
  elapsed pace). One neutral `bg-secondary-lt` pill with the gold trophy and
  « Record » sits in the header when the workout currently holds anything at
  all — the classic `records` types plus the best-effort distances, never one
  badge per family. Each row carries the trophy of its personal place
  (`DESIGN.md` §10.4): gold for the distance the workout holds — the
  `EffortRecord` is the authority — silver and bronze for the owner's second
  and third best time over that distance, derived on read by
  `BestEfforts::PersonalPlaces` (same order as the record: duration, earlier
  start, earlier row). The gold moves the moment another workout steals the
  record. Second and third places are owner-only and are never published.
- Hovering, focusing or pinning a best-effort row highlights its distance
  window on the elevation chart and the map. The tab draws no persistent
  boundaries or timeline steps: with several overlapping efforts they would
  clutter the chart, so the range only appears while a row is active.
- Distances are localized through `records.distances.<key>`; the badge uses
  `workouts.show.records.badge_short`, the tooltips `medals.record`,
  `medals.records` and `medals.personal_place.*`.
- A publication shares the held markers — gold only, never a second or third
  place — only when the profile's `records` setting is on (off by default): the
  snapshot carries `record_types` and `record_distances`, and federated Notes
  deliver them as dedicated tags (`[devdoc:federation]`). The snapshot is
  immutable, so a later record change stays invisible until the owner
  republishes.

## 6. Backfill

`BestEfforts::BackfillJob` (BATCH_SIZE 100, resumable with `after_id`,
narrowable with `sport_slug`) rebuilds efforts for existing workouts from their
stored track points — no original file, no re-analysis, no analyzer version
bump — and recomputes the affected records per batch.
`bin/rails best_efforts:backfill` enqueues it (`AFTER_ID` resumes,
`SPORT=<slug>` narrows the sweep when a profile gains a distance);
`bin/rails best_efforts:rebuild WORKOUT=<id>` rebuilds one workout now. `MC`
fills in where detected climbs already exist.

## 7. Out of scope

- Notifications or emails for a new record.
- Federating or publishing best efforts.
- Efforts bridging a recording pause, or moving-time variants.
- GAP on each effort, 50 k/100 mile distances, and per-effort rows beyond the
  single winner per distance.
