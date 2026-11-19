# Derived data contract

A workout's stored values are derived from its immutable original file or from
data derived from it. When the code or a catalogue changes, those values must be
rebuilt — without re-doing work that is still valid, and with one operator (and
owner) story instead of one button per derivation. This document fixes the map:
what is derived from what, which marker protects each derivation, and where the
rebuilds are launched.

## 1. The derivations

| Derivation | Input | Network? | Marker | Entry point |
|---|---|---|---|---|
| Import facts: recording device, re-detectable sport, virtual venue | original file + platform catalogue | no | `workouts.import_detection_version` | `Workouts::RebuildJob` |
| Analysis: metrics, track segments, best efforts, matching, detected laps | original file + sport thresholds | no | `workouts.analysis_version` | `Workouts::RebuildJob` |
| Owner route image | stored track segments (Chromium) | tiles | `workouts.route_image_version` | `Workouts::RenderRouteImageJob` |
| Toponymy | stored track segments | Nominatim | `workout_toponymies.algorithm_version` + `status` | `Workouts::ToponymyRefresh` → `Workouts::EnrichToponymyJob` |
| Assembled places | stored toponymy | no | `workout_toponymies.places_algorithm_version` | `Workouts::PlaceNamer` |
| Terrain elevation | stored track + DEM | DEM service | `workout_elevations.status` | `Workouts::ApplyElevationSourceJob` |
| Heart-rate histogram and zones | stored track segments + the owner's heart-rate profile | no | `workouts.heart_rate_version` (histogram), `workout_heart_rates.zones_fingerprint` (zones) | `HeartRates::Rebuild`, `HeartRates::RezoneJob` ([HEART-RATE.md](HEART-RATE.md)) |
| Course elevation profile | stored source track segments (frozen) | no | `segments.elevation_profile` (`NULL` = not built, `[]` = built empty) | `Segments::Creator`, `Segments::BuildElevationProfileJob` |
| Recurring-route suggestions | stored track segments | no | `workouts.route_suggestion_version` | `Segments::RouteSuggestionDetector` (`Segments::SuggestRouteJob`, `Segments::RouteSuggestionSweepJob`) |
| Workout summary | the owner-only context, the analysis, the efforts, the weather, the zones and the places | AI provider | `workout_summaries.version` + `facts_digest` | `Workouts::SummaryRefresh` → `Workouts::GenerateSummaryJob` ([AI.md](AI.md)) |

The workout-side contracts are in `WORKOUT.md`, the course-side ones in
`SEGMENTS.md`, the terrain profile in `ELEVATION.md`, the toponymy and places in
[MAPS.md](MAPS.md).

Publication route images are **not** in this table: a publication is an
immutable snapshot, its image is rendered once before delivery, and changing it
means republishing (a new identity). See `PUBLISHING.md`.

## 2. One parse per rebuild

`Workouts::RebuildJob` reconciles one workout from one parsed original, in
dependency order:

1. **facts**, when `import_detection_version` is older: fill `workouts.source`
   when empty, re-detect the sport through `Workouts::SportResolver` only when
   the import entry is still `detected` (`manual` and `fallback` are never
   overwritten), and re-locate the virtual venue — discarding a legacy
   toponymy;
2. **analysis**, when `analysis_version` is older: `Workouts::Reanalyzer`
   re-runs with the sport's thresholds and replaces track segments, recorded
   laps and best efforts; segment matching and detected laps follow through
   `Segments::MatchWorkoutJob`. A sport change during step 1 already forces
   this run, so the staleness check happens after the facts phase;
3. **places**: `Workouts::PlaceNamer` reassembles the displayed list from the
   stored toponymy (pure, no geocoding); a virtual workout is left to its
   venue;
4. **media**: `Workouts::RenderRouteImageJob` is enqueued when
   `route_image_version` is older than `Workouts::RouteImage::VERSION`.

The parsed `Track` is injected into `Workouts::Reanalyzer` and
`Workouts::SportChange`, so a facts-plus-analysis rebuild reads the file once.
A file that cannot be parsed is reported (`Rails.error`) and left un-stamped:
the workout keeps showing up in the rebuild count instead of disappearing.

## 3. Markers and staleness

- `workouts.analysis_version` — set by every import and analysis run; bump
  `Allure::Gpx::Analyzer::VERSION` when the analyzer changes. A non-forced
  re-analysis compares the stored and the recomputed coordinates and resets
  `route_image_version` to 0 only when the geometry actually changed; a forced
  run (sport change, elevation-source switch) keeps the same geometry and
  leaves the image alone.
- `workouts.import_detection_version` — set to current at import and after a
  facts pass; bump `Workouts::ImportDetection::VERSION` when the platform
  catalogue, the alias tables, or the facts rules change. Existing rows start
  at 0 and are reconciled by the next sweep.
- `workouts.route_image_version` — stamped by the render job with
  `Workouts::RouteImage::VERSION`; 0 means missing or stale. Bump the constant
  when the rendered contract changes (style, chevrons, framing, renderer
  swap). One marker covers the light and the dark variant: the job renders and
  attaches both together. A one-off migration stamped every already attached
  image as current, so the first sweep after a deployment does not re-render
  the library. A virtual world's map changing is not a renderer change:
  bumping the constant would re-render everything, so a one-off invalidation
  targets only the virtual recordings drawn on the worlds whose artwork
  changed, then queues one `Workouts::BackfillRouteImagesJob` at backlog
  priority. Publication images stay frozen.
- `segments.route_image_version` — the same marker for the owner image of a
  segment, route or loop, stamped by `Segments::RenderRouteImageJob` with
  `Segments::RouteImage::VERSION`, covering both variants. Course images are
  always smoothed at the medium level ([MAPS.md](MAPS.md)) and live on the same
  `route_images` worker; the marker is separate because the two rendered
  contracts change independently.
- `workouts.loop_reuse_version` — stamped by `Segments::MatchWorkoutJob` with
  `Segments::LoopReuse::VERSION` after loop detection. Bump the constant when
  discovery or the reuse predicate changes: `Segments::BackfillLoopReuseJob`
  re-runs every positioned recording whose marker is older, including those
  with no loop yet, discovering interior repeats and converging duplicate loop
  segments onto the oldest similar one (`SEGMENTS.md`). Every re-analysis
  resets it to 0, because new recording segments invalidate the point-indexed
  efforts until the matching job that follows stamps it again; automatic
  publishing waits on it (`AUTO-PUBLISHING.md`). A one-off reconciliation
  invalidated the positioned imports stamped by the previous discovery rule,
  then enqueued one `BackfillLoopReuseJob` at backlog priority. It does not
  delete loop identities or efforts itself; ordinary matching merges
  duplicates, rebuilds laps and removes orphaned loops. The primary
  invalidation commits before the separate queue write; enqueue failure fails
  the migration so deployment can retry safely. A fresh install with no
  eligible recordings enqueues nothing. Rollback does not undo this derived
  reconciliation.
- `workouts.elevation_source_requested` — the importer records `dem` when it
  enqueues terrain elevation for an opted-in account, so the import-time
  request is pending exactly like an owner's switch until the reanalysis
  applies it or the apply job gives up.
- Toponymy — scheduled on the server only, never by the owner's page (the
  `GET /workouts/:id/toponymy` endpoint just reads). `Workouts::ToponymyRefresh`
  marks the row `pending` (so the enricher does not skip a still-`ready` row)
  and enqueues the globally paced `Workouts::EnrichToponymyJob`; on a virtual
  workout it discards a legacy row instead. It is called:
  - at import, unless terrain elevation was requested: the importer then
    leaves a `pending` row and the re-analysis that applies the terrain profile
    geocodes once, on the final profile; when the apply job gives up, it
    geocodes on the recorded profile (a `pending` or missing row only);
  - by `Workouts::Reanalyzer` when the run changed the stored coordinates or
    the effective elevation source (the markers carry elevations). A
    same-geometry, same-profile run — a sport change — keeps the places; a
    sport change out of a virtual sport geocodes;
  - by `Workouts::ToponymyRecoveryJob`, every 15 minutes in production, for a
    `failed` row older than 6 hours and created within 2 days, and a `pending`
    row untouched for 2 hours (a lost job, or a deferred import whose terrain
    run degraded to the recorded profile), never while a terrain request is
    pending. Older failures are left to the owner's « Lieux » action and the
    operator sweep;
  - by the sweeps below after an `ALGORITHM_VERSION` bump.
- Places and elevation keep their own existing markers.
- `segments.elevation_profile` is a creation-time snapshot, not a generation
  marker: `Segments::Creator` writes it once from the exact selection, and the
  backfill only fills `NULL` rows. A source re-analysis never rewrites it — the
  segment's stored elevations are frozen exactly like its `ascent`/`descent` —
  so there is nothing to invalidate. `[]` means the builder ran and found no
  usable elevation or no matching provenance; it is never re-scanned.
- `workouts.route_suggestion_version` — stamped by
  `Segments::RouteSuggestionDetector` with `RouteSuggestionDetector::VERSION`
  after a recording is examined, whether or not it produced a suggestion. Bump
  the constant when the candidate query, the verdict, or the minimum changes:
  the sweep re-examines every positioned recording whose marker is older.
  Existing recordings start at 0, pending the audited sweep; a bulk import runs
  that sweep at the end of its batch (`SEGMENTS.md`).
- `segments.place_status` — the course's nearby place (`SEGMENTS.md`),
  geocoded once because the geometry never changes:
  `Segments::GeocodePlaceJob` is enqueued after the segment is committed and
  shares the workout toponymy's concurrency key, so the provider sees one
  paced stream. `pending` means not asked yet (also while no provider is
  configured), `ready` holds `place_name`, `unavailable` means a virtual
  course or a place the provider cannot name, and `failed` means the provider
  kept failing. `Segments::PlaceRecoveryJob` (every 15 minutes in production)
  retries a `pending` row older than 2 hours and a `failed` one older than
  6 hours, both created within 2 days; older rows wait for the operator sweep.
- `workout_summaries.version` and `facts_digest` — the assistant summary
  ([AI.md](AI.md)). `version` covers the prompt, the schema and the fact
  selection; bump `Allure::Insights::VERSION` when one of them changes. The
  digest covers the facts themselves, their locale and the unit system, so a
  detector, a locale or a units change re-generates without touching the
  constant. `Workouts::SummaryRefresh` recomputes both on every scheduling
  call and is a no-op while they match. The summary is a network derivation, so
  the sweeps below only cover the last 30 days: an archive import never queues
  months of model calls. `ready` rows beyond that window are regenerated only
  by the owner's « Régénérer ».

## 4. Sweeps

| Sweep | Scope | Batches |
|---|---|---|
| `Workouts::BackfillRebuildJob` | stale in either `analysis_version` or `import_detection_version` | id cursor, 100 |
| `Workouts::BackfillRouteImagesJob` | `route_image_version < RouteImage::VERSION` | id cursor, 100 |
| `Segments::BackfillRouteImagesJob` | `segments.route_image_version < Segments::RouteImage::VERSION` | id cursor, 100 |
| `Segments::BackfillLoopReuseJob` | positioned recordings with `loop_reuse_version < LoopReuse::VERSION`, including those without a loop | id cursor, 100 |
| `Workouts::BackfillPlacesJob` | usable toponymy with a stale place list, non-virtual | id cursor, 100 |
| `Workouts::BackfillToponymyJob` | non-virtual with no toponymy or one below `ToponymyEnricher::ALGORITHM_VERSION` (no terrain request pending), plus a legacy toponymy on a virtual workout | id cursor, 100 (schedules the paced geocoding) |
| `Workouts::BackfillElevationJob` | elevation-less, opted-in account, configured provider | id cursor, 50 |
| `Segments::BackfillElevationProfilesJob` | source-backed segments with a `NULL` elevation profile | id cursor, 100 |
| `Segments::BackfillTerrainElevationJob` | `device` courses never tried or `failed`, eligible for the terrain (`ELEVATION.md`), configured provider | id cursor, 100 (one paced `ApplyTerrainElevationJob` each) |
| `Segments::BackfillPlacesJob` | segments whose `place_status` is `pending` or `failed`, configured provider | id cursor, 100 (schedules the paced geocoding) |
| `Together::BackfillDetectionJob` | recordings whose `together_detection_version` is below `Allure::Together::Detector::VERSION` (`SHARED-ACTIVITIES.md`) | id cursor, 100 (one `DetectWorkoutJob` each, which stamps the version) |
| `HeartRates::BackfillJob` | recordings whose `heart_rate_version` is below `Allure::HeartRate::Histogram::VERSION` ([HEART-RATE.md](HEART-RATE.md)) | id cursor, 100 (inline, from the stored points) |
| `Segments::RouteSuggestionSweepJob` | positioned recordings whose `route_suggestion_version` is below `RouteSuggestionDetector::VERSION`, one sweep per account, newest first (`SEGMENTS.md`) | per-account keyset, 25 |
| `Workouts::BackfillSummariesJob` | eligible workouts started in the last 30 days whose summary row is missing, `failed`, or below `Allure::Insights::VERSION` (`AI.md`) | id cursor, 100 |

All of them are idempotent and resume themselves. Operator surfaces:

- `/admin/jobs` cards with the pending counts and one audited action per sweep
  (`workouts_rebuild_enqueued`, `route_images_backfill_enqueued`,
  `segment_route_images_backfill_enqueued`, `places_backfill_enqueued`,
  `toponymy_backfill_enqueued`, `elevation_backfill_enqueued`,
  `loop_reuse_backfill_enqueued`, `elevation_profiles_backfill_enqueued`,
  `segment_places_backfill_enqueued`, `together_detection_backfill_enqueued`,
  `heart_rate_backfill_enqueued`, `route_suggestions_backfill_enqueued`,
  `summaries_backfill_enqueued`);
- `bin/rails workouts:rebuild` (`AFTER_ID=` to resume),
  `bin/rails workouts:toponymy` (`AFTER_ID=` to resume),
  `bin/rails workouts:route_images`, `bin/rails workouts:regenerate_route_images`
  (forces every image, bypassing the marker), the same pair for courses
  (`bin/rails segments:route_images`, `bin/rails segments:regenerate_route_images`),
  `bin/rails segments:loop_reuse` for the loop reconciliation, and
  `bin/rails segments:elevation_profiles` for the course profile backfill,
  `bin/rails segments:places` for the course place backfill, and
  `bin/rails workouts:heart_rate` (`AFTER_ID=` to resume) for the heart-rate
  histograms, and `bin/rails workouts:summaries` (`AFTER_ID=` to resume) for
  the assistant summaries.

## 5. Owner-scoped rebuilds

`Workouts::UserBackfillJob(user_id, kind)` runs the same scopes limited to one
account, in batches of 25, throttled to one sweep per `(account, kind)`:

| Kind | Scope | Dispatches |
|---|---|---|
| `rebuild` | the account's stale workouts | `Workouts::RebuildJob` |
| `route_images` | the account's missing/stale owner workout images | `Workouts::RenderRouteImageJob` |
| `segment_images` | the account's missing/stale owner course images | `Segments::RenderRouteImageJob` |
| `places` | stale assembly, or missing/pending/failed/outdated toponymy (non-virtual) | `RebuildPlacesJob` or `ToponymyRefresh` |
| `elevation` | `BackfillElevationJob` scope, limited to the account | `ApplyElevationSourceJob` |
| `loops` | `BackfillLoopReuseJob` scope, limited to the account | `Segments::MatchWorkoutJob` |
| `heart_rate` | `HeartRates::BackfillJob` scope, limited to the account | `HeartRates::Rebuild`, inline |
| `route_suggestions` | `RouteSuggestionSweepJob` scope, limited to the account | `Segments::RouteSuggestionSweepJob` (one newest-first walk) |
| `summaries` | `BackfillSummariesJob` scope, limited to the account ([AI.md](AI.md)) | `Workouts::SummaryRefresh` |

The settings page **Données et recalculs** (`/settings/data`,
`Settings::DataController`) shows one counter per kind — refreshed through the
shared `live-frame` polling — and one confirmation-guarded button per kind. A
per-workout **Régénérer l'image** action lives in the workout header menu. A
user sweep never bypasses a contract: it only rebuilds to the state the current
code and catalogue already define, and never touches another account's rows.

## 6. What this deliberately does not do

- No publication image re-render: snapshots are immutable, and a Create intent
  can only be finalized while it is `preparing`.
- No geocoding inside a rebuild sweep: the toponymy is paced by its own job,
  and the re-analysis, the toponymy sweep and the user "places" action only
  schedule it.
- No geocoding triggered by reading a page.
- No per-phase buttons in the interface: one rebuild action, one image action,
  plus the existing places and elevation ones for their specific
  prerequisites.
