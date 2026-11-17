# Positionless recordings contract

An indoor or positionless recording is a real activity with real figures:
distance from a trainer, speed from a footpod, power from an erg, heart rate
from a strap. Rejecting the whole file because it has no fix discards
everything the device measured. Allure imports it, measures it from the
device's own records, and shows it without any geometry. This document defines
the classification, the device readings, the analysis, the persistence, the
skipped derivations, the publication refusal and the presentation.

## 1. Intent and non-goals

Non-goals, deliberately:

- no fabricated geometry: no placeholder coordinates, no bounds, no route
  image, no map, no "0,0" island;
- no publication, federation, or ActivityPub representation of a positionless
  recording (§7 reserves it);
- no geocoding, terrain elevation, segment matching, loop reuse or co-presence
  detection for it;
- no manual entry without a file: this contract is about imported files. A
  workout typed in by hand is its own origin, `manual`, specified by
  `[devdoc:manual-entry]`; it shares this contract's refusal to publish.

## 2. Concepts

| Concept | Meaning |
|---|---|
| Positioned recording | `origin: "import"`, a track with coordinates |
| Positionless recording | `origin: "import"`, no coordinate anywhere |
| Positional geography | `start_point`, `bounds`, `track_segments.geom`, the map, route images, toponymy, places, terrain elevation, segment matching |

A recording is one or the other, never both: a file whose position coverage is
too thin is imported positionless (§3.1) and its stray fixes are stripped, so
no segment mixes coordinates with positionless points.

## 3. Parsing contract

### 3.1 Classification

- FIT and TCX keep **every timed record**, coordinates or not: their heart
  rate, cadence, power, speed and cumulative distance are analysed.
- A file is **positioned** when at least two of its timed records carry a fix
  and either at least half of them do, or fixes fall in at least half of the
  minutes that hold a record; otherwise it is **positionless**. The ratio keeps
  a brief lock (a window, a tunnel exit) from turning an indoor recording into
  a meaningless two-point track and discarding every other reading. The minute
  coverage keeps devices that record every second but fix only every few
  seconds positioned: their fixes span the whole activity. A positioned file
  keeps its positioned segments alone: the pre-lock records stay skipped.
- The rule is a per-file classification, not per-segment: no workout changes
  shape when re-analysed, because a positioned file's surviving records are
  the same ones.
- `Allure::Gpx::NoTrackError` means "fewer than two timed records": a file with
  no usable data at all. The localized message says so.
- GPX and KML cannot express a positionless point, so they are not affected: a
  `<trkpt>` without `lat`/`lon` is still malformed.

### 3.2 Device readings

- FIT `record.distance` (field 5, centimetres) is decoded as the point's
  cumulative device distance in metres; TCX reads the trackpoint's
  `DistanceMeters` and its TPX `Speed`; FIT keeps using
  `enhanced_speed`/`speed`.
- A device reading is used only when finite and non-negative; a backward
  cumulative step is a reset, not negative ground, and reads as a standstill.

### 3.3 Indoor sport catalog

Two sports serve duration-only sessions, which no other entry could name
honestly (they would otherwise import under the selected fallback):

| Slug | Label | Group | FIT |
|---|---|---|---|
| `strength_training` | Strength Training | other | `training/strength_training` |
| `fitness` | Fitness | other | `training` and its cardio/yoga sub-sports, `fitness_equipment` and its elliptical/stair sub-sports |

Both record no elevation and no power column, ship their own inline SVG
partial, and are their own co-presence family. Trainer rides, treadmill runs
and erg sessions keep their existing entries (`cycling_virtual`,
`running_virtual`, `rowing_virtual`).

## 4. Analysis

`Allure::Gpx::Analyzer` measures a positionless segment without coordinates:
no outlier removal, no elevation profile, no grade-adjusted pace, no geodesic
distance. Distances and speeds are stored in SI as for every recording.

### 4.1 Distance and speed

- The device's cumulative distance is authoritative; the offset is dropped by
  taking the first record as the origin (trainers and ergs count from their
  lifetime total).
- Where a record has no cumulative distance, the interval is the device speed
  over its own duration; where neither is recorded, the interval has distance
  0. A distance step fills a missing speed.
- Point speed (`"v"`) is the device's own reading, falling back to the
  interval it ends. A value that rounds to 0 is omitted, so `v` never claims
  motion that did not happen.
- Maximum speed still prefers the device's session maximum
  (`Allure::Gpx::MaxSpeed` over the intervals otherwise).

### 4.2 Moving time

- The stopped-speed threshold decides, as for a positioned recording, as soon
  as the file recorded any movement data (a cumulative distance or a speed).
- A file with neither is a **duration-only** session: its timer ran, so all of
  its time is moving time and the only pause is a recording gap between
  segments (FIT timer stops, the one pause a TCX cannot express).

### 4.3 Elevation, anomalies, and figures

- `ascent`, `descent`, `min_elevation` and `max_elevation` are 0/nil: no
  elevation is recorded, and the device's own totals are still used when the
  session or complete laps carry them (`ELEVATION.md`).
- The anomaly pass evaluates the time, heart-rate, power and cadence families
  only: the GPS family (rejected fixes, jumps, timestamp skew, implausible
  speed) never runs, and nothing is marked major, because no coordinate-derived
  figure can be wrong.
- Best efforts, splits, recorded laps, pauses, stops, speed and power
  intervals and detected laps are all derived from distances and times exactly
  as for a positioned recording, so a trainer ride keeps its efforts and
  records.
- `bounds` and `start_point` stay nil; the workout is stored without them.

## 5. Persistence

- `workouts_recording_shape` reads: a recording always has `points_count` and
  `import_format`, and has both `start_point` and `bounds` or neither. A credit
  row keeps its own branch unchanged.
- `track_segments.geom` is nullable. A positionless segment has no geometry
  and no coordinates in its serialized points (`PointSerializer` omits `lat`
  and `lon` rather than writing null: every coordinate consumer fails loudly
  instead of reading a meaningless 0° position).
- `Workout#positioned?` is `start_point.present?` on a recording; the
  `positioned` and `unpositioned` scopes compose with the existing
  `recordings` scope. `TrackSegment#positioned?` is its geometry.

## 6. Derivations

The importer persists the workout and its points, then skips everything
geographic: no virtual venue, no route image, no segment matching, no
co-presence detection, no terrain-elevation request, no toponymy. Its smart
laps and records are rebuilt by `Laps::RebuildJob` instead, and the loop
generation is stamped at import.

`Workouts::Reanalyzer` and `Workouts::RebuildJob` handle the empty shape, and
every geometry sweep scopes to `positioned`: route images, toponymy, places,
terrain elevation, loop reuse, co-presence, and the per-account backfill. The
geometry endpoints (`track`, `toponymy`, route-image regeneration, course and
route creation, the elevation-source switch) answer 404 for a positionless
workout.

## 7. Publication and federation

A positionless recording is **not publishable**: `Workouts::PublicationReadiness`
reports `no_geometry` and `Workouts::PublicationCandidate` refuses with the
same code before any privacy work, the workout page offers no publish form,
and automatic publishing skips it with a `no_geometry` ledger reason.

Sharing a route-less activity needs its own contract: a Note without a route
or location, no GPX and no route-image attachments, `has_route: false`, an
amended `FEDERATION.md`, and the strict Allure Note parser taught to accept
it. Until that contract exists, `no_geometry` is the refusal. The same refusal
covers a manual entry (`[devdoc:manual-entry]`), and the same future contract
would publish both.

## 8. Remote import sources

A provider's listing that declares no track (`hasPolyline: false`) or is an
indoor activity is imported: its file is fetched and imported positionlessly.
Only an activity the provider holds **no file** for (a manual entry) is
skipped, as `no_file`. One exception: a remote connection may import
**positioned sessions only** (`import_connections.positioned_only`,
`REMOTE-IMPORTS.md`): a listed entry without a route is skipped as
`no_geometry` before any fetch, and a session announced with a route but
answered with fewer than two positions raises
`Allure::RemoteImports::Error::NoGeometry`, skipped as `no_geometry` too; with
the flag off, positionless sessions import as everywhere else.

## 9. Presentation

- The owner's page drops the map rail for a positionless workout, so the
  summary leads the single column; a neutral « Sans position GPS » pill names
  the state in the header.
- Elevation tiles never appear. A duration-only session also drops the
  distance and pace/speed tiles and promotes power, heart rate and calories
  instead; its chart plots **elapsed minutes** instead of kilometres.
- The route image is never rendered: the workout card shows the no-position
  state rather than a pending skeleton, and the list shows a dash where the
  file recorded no distance or elevation.
- The analysis card hides the Segments tab (no effort exists) and keeps the
  laps, splits, intervals and best-effort tabs.
- The sharing card states that the workout has no route to share, and the
  workout table shows no place.

## 10. Verification

- FIT and TCX parser specs: positionless retention, the classification rule,
  cumulative distance, TPX speed.
- Analyzer specs: trainer with distance and speed, duration-only moving time,
  frozen and backward cumulative distances, no bounds, no elevation, no
  anomalies.
- Importer and request specs: the positionless shape, the skipped derivations,
  the geometry endpoints answering 404, the list and page states, and the
  publication refusal.
- `spec/requests/workout_positionless_spec.rb` is the exit gate for the
  browser-facing contract.
