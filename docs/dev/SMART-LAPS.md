# Smart laps contract

The derived "smart lap" layer: loops and routes projected from efforts,
recording pauses, climbs and descents, stops, and speed or power intervals,
rendered owner-only beside the recorded laps and splits. `SEGMENTS.md` is the
authority for segments, routes, loops, efforts, splits and leaderboards; this
document fixes the detected-lap contract, the detector catalog and the merged
laps/climbs/splits surface.

## 1. Intent and non-goals

A workout should explain itself without the athlete carving it by hand: which
segments were repeated, where the pauses fell, which sustained climbs and
descents the elevation profile contains, where the athlete stopped, and which
effort blocks stand out. Those derived slices are **smart laps**.

Non-goals, deliberately:

- no automatic creation of shareable segments or routes. A smart lap is
  analysis, not a course. The segment/route separation stands;
- no federation, publication, timeline or public rendering of any smart lap;
- no cadence-block detector: cadence is often absent and reads rpm/spm;
- no user-configurable thresholds, FTP or heart-rate zones in this contract;
- no map highlighting or "save this climb as a segment" action.

## 2. Concepts

Four lap concepts coexist and must never be conflated:

| Concept | Storage | Source | Visibility |
|---|---|---|---|
| Recorded lap | `laps` | FIT `lap` / GPX `<lap>` | Owner-only |
| Loop effort | `segments` + `segment_efforts` `kind: loop` | `LoopCandidates` + matcher, shared across the owner's workouts closing the same circuit | Owner-only, private |
| Split | computed per request | `Allure::Gpx::Splits` | Owner-only |
| **Detected lap** | `detected_laps` | projection, pauses, elevation, speed, power | Owner-only |

A detected lap is display-only: never URL-addressable, no ShortUUID, never a
publication representation, never federated. It is fully rebuildable from the
immutable track and the existing efforts.

## 3. Data model — `detected_laps`

Columns: `workout_id` (cascade), `segment_effort_id` (nullable, `SET NULL`),
`source`, `number`, `start_point_index`, `end_point_index`, `start_distance`,
`end_distance`, `started_at`, `elapsed_time`, `moving_time`, `distance`,
`ascent`, `descent`, `average_speed`, `average_pace`, `max_speed`,
`grade_adjusted_pace`, `average_heart_rate`, `max_heart_rate`,
`average_cadence`, `average_power`, `max_power`, `average_grade`, `max_grade`,
`climb_score`, `detector_version`, `name`.

Frozen rules:

- `source ∈ loop | route | pause | climb | descent | stop | speed_interval |
  power_interval`;
- `number` is unique per `(workout_id, source)` and orders rows from one;
- `end_point_index > start_point_index`; `end_distance >= start_distance`;
- `elapsed_time > 0`; `moving_time BETWEEN 0 AND elapsed_time`;
- every metric is non-negative when present; `distance >= 0` so a zero-metre
  stop is representable;
- `name` is the persisted, geocoded label (≤ 120 characters) and stays null
  when no place was found; the view falls back to its generic source label;
- point indexes are indexes into the workout's flattened `PointStream`, shared
  with efforts, so a detected lap and an effort describe the same geometry.

## 4. Detectors

All detectors are pure Ruby under `lib/allure/laps/`, fed by
`Allure::Segments::PointStream`; persistence and orchestration live in
`Laps::Rebuild`.

### 4.1 Loop and route projection

Each loop or route `SegmentEffort` becomes a detected lap carrying the effort's
metrics and `segment_effort_id`. A loop segment is shared by every one of its
owner's workouts that closes the same circuit, reused instead of recreated
(`SEGMENTS.md` §4.3), so the projected laps stay per-workout while the course
stays single. A route is only projected when it was matched at least twice; a
single route traversal is the workout itself, not a lap. Route repeats
currently require a matcher extension (see §10), so the route source is a ready
path rather than a live one.

Loop discovery also searches inside the recording: approach and return legs are
excluded, at least two complete same-direction tours are required to create a
new loop, and incomplete tours are not projected. One complete same-direction
traversal of an active loop already owned by the account is recognized
independently of discovery and projected as a single detected lap. A tour never
bridges a recording gap. Only one circuit is retained per workout, selected by
validated coverage and elementary-tour count (`SEGMENTS.md` §4.3). Re-running
the detection/reuse backfill rebuilds these projected laps without touching
publications.

### 4.2 Pause laps

When a workout has at least two recording segments, each segment becomes one
pause lap. A single uninterrupted recording is not lapped. Metrics are copied
from the stored `track_segments` row; no re-analysis. Zero-distance or
zero-duration segments are skipped.

### 4.3 Climbs and descents

`Allure::Climbs::Segmenter` is the single elevation-profile definition, used by
the smart-lap detectors **and** by toponymy sampling (§5). One profile, `LAP`:
50 m bins, 30 m minimum gain, 400 m minimum length, 30 km maximum length (a
long alpine climb such as the Alpe d'Huez, 14 km, or the Ventoux, 21 km, has no
intermediate local minimum, so a shorter cap loses it entirely), 3 % minimum
average grade, latest local minimum as the start, and a forward extension pass
that reaches the true top while the running maximum holds within a 20 m drop
budget (up to 1 km). The extension may dilute the average grade to 90 % of the
floor; a longer, flatter tail falls back to the pre-extension peak. A climb
never passes over a point higher than its peak: the backward search for its
start stops there. The selection keeps the strongest climbs (gain plus
prominence), never two that overlap.

The profile consumed here is the stored canonical `ele` (`WORKOUT.md` §6.6):
the analyzer already removed the GPS noise once, so the segmenter's resample
and boxcar pass only shape the detection, and the reported ascent comes from
the threshold accumulator in `Laps::Metrics` using the workout's
`elevation_filter` class.

The profile is built over one continuous run of ground at a time: a recording
segment boundary is a pause (the athlete stood still, the ground continues) or
a teleport (the platform moved them, the ground does not). `ElevationDetector`
breaks the profile at a boundary whose positions jump 200 m or more, so a climb
never spans a teleport and its jump is never counted as ascent
([VIRTUAL-PLATFORMS.md](VIRTUAL-PLATFORMS.md)); a climb that spans a pause stays one climb.

`ClimbDetector` projects each climb onto point indexes and computes slice
metrics, average and maximum grade, and a climb score (`km × average grade %`).
`DescentDetector` mirrors it on the inverted elevation profile: the segmenter's
peak is the real bottom and its gain is the real loss. Stored grades stay
positive; the source carries the direction. Sports without recorded elevation
yield neither source.

### 4.4 Stops

`StopDetector` finds runs of near-zero speed inside one recording segment.
Speed is derived from distance and time deltas, never from the optional point
speed field. The sport's `stopped_speed_threshold` starts a stop; a 5 s exit
window above the threshold confirms its end, and the block must last at least
30 s. A recording gap splits or discards the block. A stop carries duration,
near-zero distance and heart rate, with `moving_time` zero. Its ascent and
descent use the canonical filtered profile and the workout's `elevation_filter`
threshold.

### 4.5 Speed and power intervals

`IntervalDetector` is the shared hysteresis engine: enter once the smoothed
value holds `enter` for the minimum duration, leave once it drops below `exit`
for the minimum recovery, and always stop at a recording gap. Smoothing is a
centered 20 s average.

`Allure::Laps::Profiles` sets absolute floors per `sport.colour_group`
(run/ride/hike/swim/ski/other) and the workout percentile raises them:
`enter = max(group floor, p85)`, `exit = max(group floor, p70, 0.75 × enter)`.
A slow session therefore invents no intervals and a fast one is not capped
below its own level.

- `SpeedIntervalDetector` uses the derived speed series (minimum 30 moving
  values) and detects sustained fast blocks;
- `PowerIntervalDetector` runs only for sports with `records_power` and enough
  positive samples (minimum 60); missing samples and zeros pull the series
  down, so a sensor dropout ends a block.

Intervals are never geocoded; the tab labels them by source and number.

### 4.6 Precedence

Overlapping laps keep the higher-precedence source: `route` > `loop` >
`pause`. Every other source lives in its own tab and is only de-overlapped
within itself, earliest start first.

## 5. Toponymy consolidation

`Allure::Toponyms::SampleTrack` samples `climb_summit` at the tops of the same
climbs the Montées tab lists. `Workouts::ToponymyEnricher::ALGORITHM_VERSION` is
7, so an existing toponymy is stale and re-enriched lazily when the owner next
opens the workout; this is the one change that may consume new geocoding calls
at scale.

`Allure::Laps::Namer` labels loop, pause, stop, climb and descent from the
stored toponymy — curated `markers` first, then `climb_summit` samples, then
`start_place`. No additional geocoding request is ever made.

- climb → best place within 750 m of the top;
- descent → a pass or summit within 750 m of the top, else the nearest place
  to the bottom;
- loop → best marker inside the loop, then the nearest place to its start, then
  the start place;
- pause and stop → nearest place within 1 km of the start;
- route and intervals → never geocoded.

`Laps::Naming` persists the name for every source and clears a stale one. It
runs at the end of `Laps::Rebuild` when a toponymy is already usable, and at
the end of `Workouts::ToponymyEnricher#call` when enrichment lands or refreshes
one, so the latest enrichment always wins without a naming job.

`Workouts::PlaceNamer` is the workout-level counterpart: from the same stored
toponymy it assembles the displayed three-entry list and the indexed
`workout_place_names` rows the owner's place filter and autocomplete search,
never making a geocoding request (`WORKOUT.md` §9.1). It runs at the end of
enrichment, and `Workouts::BackfillPlacesJob` recomputes existing rows through
the audited `/admin/jobs` action.

## 6. UI

`workouts/show` renders one owner-only card, **Analyse**. Only sources with rows
render a tab, and the card opens on the first one:

1. **Segments** — the workout's matched segment efforts (PB badge, gap to the
   personal best, deviation on wide cards);
2. **Tours détectés** — loop, route and pause laps;
3. **Montées** — climbs;
4. **Descentes** — descents;
5. **Arrêts** — stops;
6. **Efforts** — speed and power intervals with a source badge;
7. **Tours enregistrés** — the file-recorded laps;
8. **Intervalles** — the existing splits.

Every tab label carries its row count. Hiding empty tabs is what keeps a
single-climb workout from opening on an empty "Tours détectés"; it now opens on
Montées.

The tables share one column vocabulary: the sport-preferred pace or speed
(`pace_speed_display`, with `pace_and_speed` adding a quiet speed secondary),
the grade-adjusted pace (`WORKOUT.md` §6.8) as a quiet second line under the
pace for qualifying sports, D+ and D− everywhere (zero when recorded and flat),
then source-specific columns, then HR, cadence and power, each rendered only
when at least one row carries the value. Splits carry their own elevation gain
and loss.

Tabler `nav-tabs` markup is driven by `workout_tabs_controller.js` (manual
`aria-selected`/`hidden` management plus arrow/Home/End keys); all panes are
server-rendered, so switching costs no request. The active pane broadcasts its
chart data and route steps as `allure:analysis-tab-changed`:

- **climbs and descents** send a summit pictogram (mountain glyph in a rose
  pill anchored on the elevation curve, with the geocoded name on desktop) at
  the summit — the climb's end, the descent's start — because a segment is a
  range and only its top is a point. They never draw vertical lines;
- **stops** send stop markers, drawn as rose pills with a pause glyph on the
  chart and as small stop panels on the map while the Arrêts tab is active;
- **detected laps, intervals, recorded laps and splits** send dashed vertical
  boundaries. Splits and recorded laps are unlabelled; detected laps and
  intervals label their start with their number.

The chart strictly follows the active tab. Toponymy place markers are always
drawn; every other layer — boundaries, stop panels, climb and descent
pictograms — belongs to the selected tab alone. Toponymy `climb_summit` glyphs
are never drawn: on the climbs tab the tab's own markers are the summits, with
their geocoded names. The solid hover cursor stays on top.

Hovering, focusing or pinning a row broadcasts its distance range as
`allure:analysis-highlight` (plus the source and, for stops, the duration).
Every row of every tab carries `data-analysis-range`, `data-start-distance`,
`data-end-distance`, `data-analysis-source` and optionally
`data-analysis-label`, and is focusable; segment efforts derive their range
from their point indexes and the desktop table row and mobile card item share
the same values (recorded laps reuse the boundary scaling; splits are
cumulative). The chart shades the range as a translucent band under its
boundaries and pictograms, and a hovered stop adds its duration panel. The map
draws the matching slice by binary-searching each recording segment's aligned
distance array and interpolating the endpoints, one line per intersected
segment, so a range straddling a pause never draws across the gap; the
segment-selection overlay is reused because the workout page never drives a
selection. A hovered or pinned stop enlarges its panel and reveals its
duration. Tap or click pins a range (the row gets `table-active`), a second tap
unpins it, and Escape clears it; hover and focus preview over the pinned range
while active. Switching tabs drops a highlight that belongs to the pane being
left.

The route timeline below the chart mirrors the same state: the toponymy steps
(start, ranked places, finish) are always listed, plus the active tab's
discrete events (climbs, descents, stops, detected and recorded laps, segment
efforts). Its step dots are the same circles as the numbered places, filled
primary and carrying the step's icon — the summit for climbs and descents, the
pause for stops — so the marker language matches the chart. Uniform splits and
intervals stay in their table only. The proportional timeline scrolls
horizontally when its steps do not fit on desktop and stacks vertically on
phones. Hovering or focusing a step previews its range on the chart and the
map; the pinned row resumes the highlight when the pointer leaves.

The sticky section nav keeps one `section-laps` anchor, labelled Analysis, and
no longer carries a separate Segments entry. Every locale carries every string.

## 7. Privacy and publication boundary

Detected laps are read through the owner-only branch of
`WorkoutsController#show`; a non-owner page renders none of the card. Nothing
in `Workouts::PublicationCandidate`, the timeline, the public show page or the
federation path reads `detected_laps`. Place names persisted in `name` inherit
that boundary and are deleted with the workout.

## 8. Lifecycle

- `Laps::Rebuild` deletes and re-inserts every detected lap for one workout in
  the `Segments::MatchWorkoutJob` transaction, after loop detection. The
  rebuild is deterministic and idempotent; row identities are not stable by
  design.
- `detector_version` invalidates rows when the algorithm changes; it is now 5.
- `Workouts::ReanalyzeJob` re-enqueues `Segments::MatchWorkoutJob` after
  reanalysis, so rewritten track segments rebuild efforts and detected laps.
- `Laps::BackfillJob` rebuilds existing workouts in bounded, resumable
  batches; it is an operator run, not an import hook. Run it after changing the
  detector version or the consolidated toponymy algorithm.

## 9. Verification

- Unit: extension reaches the true top; descent mirror; stop duration and gap
  splitting; speed and power hysteresis with percentile floors; namer rules;
  the toponymy wrapper behavior preserved through the consolidated segmenter.
- Model: source catalog, per-source numbering, point/distance/power checks,
  cascade, effort nullification.
- Service: loop projection, pause laps, climbs, descents, stops, speed and
  power intervals, route projection with two efforts, precedence,
  disjointness, idempotency, naming.
- Request: only non-empty tabs render, the first has data, counts are present,
  and a non-owner sees nothing.
- Browser: tab switching, table/card layouts, pictograms on elevation tabs,
  dashed boundaries elsewhere, keyboard arrows, light and dark themes.

## 10. Out of scope

- **Loop closure.** `LoopDetector` closes at 30 m and requires two traversals;
  the circuit closes at 38 m and is traversed once. Raising the radius to ~50 m
  and accepting a single circuit as one loop lap is a separate decision.
- **Route repeats.** `Allure::Segments::Matcher` matches a route end to end
  once. Projecting repeated routes needs a repeat-aware route matcher; the
  projection path is implemented and specced against fabricated efforts.
- Climb categories (Cat 4–HC), a grade series on the chart, map highlighting of
  a selected lap, and "save this climb as a segment".
- Cadence-block detection and configurable thresholds (FTP, HR zones).
  Heart-rate zones exist as a per-workout « Zones cardiaques » tab
  (`[devdoc:heart-rate]`); zone-driven detected intervals stay out of scope.
- The legacy loop fallback (`Workout#loop_efforts` and the old
  recorded-else-loop table) was removed; loop efforts now reach the page only
  as detected laps.
