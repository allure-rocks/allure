# Terrain elevation contract

Some recordings carry no altitude, or a profile too coarse to analyse. Allure
can fill an elevation-less workout from an external Digital Elevation Model
(DEM), and let an owner choose the terrain profile instead of the device
profile for any workout. This document defines the provider contract, the
sampling and profile rules, the device totals, the data model, the pipeline,
the surfaces and the course terrain. It does not change the analyzer algorithm
for recorded profiles, publication snapshots, or federation.

## 1. Scope and decisions

- **Provider**: OpenTopoData only, addressed by `ELEVATION_BASE_URL`. The
  operator self-hosts it; the public instance is rate-limited, so self-hosting
  is the recommended deployment. No other elevation API is supported.
- **Two-level opt-in**: the feature exists only when `ELEVATION_BASE_URL` is
  set; every account additionally carries
  `users.elevation_enrichment_enabled` (default `false`). Unset or disabled
  means no coordinate ever leaves the instance.
- **Automatic when empty**: a workout whose recorded profile has no valid
  elevation is enriched automatically after import when the sport has
  `records_elevation: true` and the owner opted in. Exact-zero placeholders on
  a partially recorded segment are not a profile (`WORKOUT.md`), so such a file
  counts as empty.
- **Choice when recorded**: a workout with recorded elevation keeps the device
  profile by default — and the device's own totals when the file carries them —
  the owner may switch it to the terrain profile per workout and switch back at
  any time. The terrain profile is never the automatic default for a recorded
  workout: a coarse DEM's short-wavelength error accumulates over long routes
  and overcounts them.
- **No federation impact**: `elevation_source` stays local. Published
  representations keep their existing fields; existing publications never
  change when the source changes.
- Missing elevation is never fabricated by the analyzer. A DEM profile is a
  distinct, explicitly chosen source applied **before** analysis; the
  "never bridge missing values" rule of `WORKOUT.md` still governs the analyzer
  and the recorded profile.

## 2. Provider contract

`GET {ELEVATION_BASE_URL}/v1/{dataset}?locations=lat,lon|lat,lon&interpolation=bilinear`

- `ELEVATION_DATASET` selects the dataset (recommended `mapzen` for global
  coverage including bathymetry; `srtm30m` is limited to latitudes −60..60).
- `interpolation` is `bilinear` by default; `nearest` and `cubic` are accepted.
- Response: `status` (`OK`, `INVALID_REQUEST`, `SERVER_ERROR`) and
  `results[].elevation`, which may be `null` outside the dataset bounds.
- A request carries at most 100 locations.
- `Allure::Elevation::OpenTopoData` maps 4xx/`INVALID_REQUEST` to a
  non-retryable `InvalidRequestError` and 5xx/429/transport/parse failures to a
  retryable `UnavailableError`. `null` stays `nil`; it is never converted to 0.
- Timeouts: 5 s open, 10 s read, 15 s total; responses are capped at 256 KiB.

## 3. Sampling and profile

Implemented in `lib/allure/elevation/`:

- `TrackGeometry.cumulative_distances` chains segments in document order: the
  straight-line horizontal distance between the last point of one segment and
  the first point of the next continues the workout-wide axis.
- `Sampler.call(segments, interval_metres:)` selects the first point, then one
  point every `ELEVATION_SAMPLE_METRES` (default 50 m) of cumulative distance,
  plus the final point. Stationary stretches do not advance the distance, so a
  pause cannot consume provider budget. `Sampler.chunks` batches at most 100
  locations without reordering.
- `Profile` interpolates linearly on cumulative distance inside contiguous runs
  of valid samples only: a `nil` sample breaks the run, so a missing raster
  never fabricates terrain across the hole. A distance outside every run has no
  elevation.
- `TrackOverride.call(track, profile:)` returns a new track whose points carry
  the profile value; points without coverage keep no elevation and the source
  track is never mutated. For `dem`, this is a **full replacement** of the
  recorded profile, not a gap fill.
- A DEM profile is analysed with its own class (`elevation_filter: "dem"`): an
  80 m smoothing half-window and an **8 m** ascent threshold. The interpolation
  is smoother than a barometer yet carries several metres of model error, and
  accumulating that error over a long route inflates ascent, so the threshold
  is coarser than the device class.

## 4. Device totals

The device's own ascent/descent wins over the computed profile when the file
carries it:

- the sum of the recorded **laps** when they all carry values and cover at
  least 95 % of the activity distance, or
- the FIT **session** `total_ascent`/`total_descent` (`Allure::Gpx::Track`'s
  `source_ascent`/`source_descent`) when the laps are missing or incomplete.

Complete laps win as the finer-grained record; the session summary is the
fallback for a file whose laps are missing or incomplete.

A **virtual world** is the exception: its elevation is rendered, not measured
by a barometer, and the platform's summaries are unreliable. A virtual sport
therefore ignores the device totals entirely and keeps the computed profile —
the same one the elevation chart draws, which keeps the D+ tile and the chart
in agreement.

Session field numbers are one above the lap numbers for the power and elevation
totals (session 21 `max_power`, 22 `total_ascent`, 23 `total_descent`; lap 21
`total_ascent`, 22 `total_descent`). The parser must read each at its own
number: a session total read at a lap number would store a power maximum as
ascent. No device family is distrusted; the computed profile remains the
fallback.

A device run uses those totals; a `dem` run ignores them entirely. GPX/TCX/KML
files carry no totals and keep the computed value.

## 5. Data model

| Column / table | Definition |
|---|---|
| `users.elevation_enrichment_enabled` | boolean, not null, default false |
| `workouts.elevation_source` | string, not null, default `"device"`; effective source of the last analysis |
| `workouts.elevation_source_requested` | string, nullable (`device`/`dem`, nil = automatic) |
| `workouts.recorded_elevation` | boolean, not null, default false; the recorded profile has valid, non-placeholder elevations (`WORKOUT.md`) |
| `workout_elevations` | one row per workout: `provider`, `dataset`, `algorithm_version`, `status` (`pending`/`ready`/`partial`/`unavailable`/`failed`), `samples` jsonb (`distance`, `latitude`, `longitude`, `elevation`), `last_error`, `generated_at`, `requests_count` |

The samples row is the cache: switching sources never re-fetches, and
reanalysis reuses the stored samples.

## 6. Pipeline

1. `Workouts::Importer` parses, analyses and persists as today, using the
   device's own totals when the file carries them. After commit it enqueues
   `Workouts::ApplyElevationSourceJob` with `"dem"` when the sport records
   elevation, the owner opted in, the provider is configured, and the recorded
   profile has no valid elevation.
2. `Workouts::ElevationEnricher` samples, fetches in chunks with a configurable
   throttle (`ELEVATION_REQUESTS_PER_SECOND`, default 5; set it to 1 for the
   public OpenTopoData instance), stores the samples and their status, and
   bounds the whole run (5 minutes).
3. `Workouts::ApplyElevationSourceJob` guarantees the samples exist, then runs
   the forced reanalysis that applies the target source; a provider that
   answers nothing usable leaves the effective source and the metrics
   untouched.
4. `Workouts::Reanalyzer` re-parses the original file, applies
   `TrackOverride` and forces the `dem` class when the source is `dem`, uses
   the device totals on a device run, and persists `elevation_source`, the
   metrics, segments and laps in the same transaction.
   `Segments::MatchWorkoutJob` then rebuilds efforts, loops, records and best
   efforts, as the sport-change path already does.
5. Failures leave the effective source untouched; the row records
   `partial`/`unavailable`/`failed` with `last_error` and the workout page
   offers a retry.
6. Every rule that changes persisted metrics bumps
   `Allure::Gpx::Analyzer::VERSION`, so `Workouts::BackfillRebuildJob`
   reanalyzes every older workout. Existing publications keep their immutable
   snapshot.

## 7. UI and copy

- Settings gains an « Altitudes » page (`/settings/elevation`), reachable from
  the settings hub only when the provider is configured, with the opt-in
  toggle and the mandatory privacy copy (`DESIGN.md` §19.18): sampled
  coordinates are sent to the configured third-party service, results are
  cached on the instance, browsers never contact it, and privacy zones do not
  filter the outbound request.
- The owner workout page shows an « Altitudes estimées (MNT) » badge when the
  effective source is `dem`, and a single source-toggle entry in the header
  `⋯` menu (« Passer aux altitudes du service » / « Revenir aux altitudes de
  l'appareil ») when the workout has recorded elevation, the provider is
  configured and the owner opted in. Pending, failed and retry states follow
  `DESIGN.md` §11.3 and render inside that menu.
- A workout with no elevation and no enrichment keeps the existing
  `workouts.show.chart.unavailable` message. The owner's summary additionally
  shows a one-line notice that names the cause and carries the single action
  that fixes it: the sport does not record elevation; the instance has no
  provider; the account has not opted in (linking to `/settings/elevation`);
  the enrichment is pending; the enrichment failed or covered nothing (both
  retrying the `dem` request); or the cached terrain profile is ready but not
  applied yet (estimating it). Non-owner pages never render the notice.
- A request that cannot succeed never leaves the page pending:
  `Workouts::ApplyElevationSourceJob` clears `elevation_source_requested` when
  the terrain profile is unusable and when the job is terminally discarded, so
  the failed/unavailable state and its retry stay reachable.
- The anomalies card's elevation mismatch ends with the same terrain-profile
  switch, where the instance and the account allow it (`DESIGN.md`).
- Source changes do not update existing publications; the control carries the
  same permanent hint as the sport change.

## 8. Operations

- `ELEVATION_BASE_URL` (unset disables the feature), `ELEVATION_DATASET`,
  `ELEVATION_INTERPOLATION`, `ELEVATION_SAMPLE_METRES`,
  `ELEVATION_REQUESTS_PER_SECOND`, `ELEVATION_MAX_REQUESTS_PER_WORKOUT`. The
  operator documentation carries their defaults and the deployment notes.
- Self-hosting OpenTopoData on the Compose network (e.g.
  `ELEVATION_BASE_URL=http://opentopodata:5000`) is the recommended deployment;
  the client is not the federation transport, so private addresses are allowed.
- `Workouts::BackfillElevationJob` and an admin action enrich existing
  elevation-less workouts of opted-in owners, throttled and resumable by id
  cursor like `Workouts::BackfillRebuildJob`. The account can also queue its own
  activities from `/settings/data`.

## 9. Courses

A course (`Segment`) carries one reference elevation profile for every athlete
who rides it: its `ascent`, `descent`, extremes, signed grade and stored
profile are the course's, and an effort on a reusable segment displays them
instead of its own recording's (the effort keeps its own measure in the API,
webhooks and MCP; loops and routes keep it in the page too, since their laps add
up to the workout's totals).

- **Terrain by default.** When the provider is configured, the terrain profile
  replaces the device's: for a **public** course with the provider alone — its
  line is already visible to every member —, for a private or followers-only
  course only with the owner's `elevation_enrichment_enabled`. Virtual sports
  and sports without elevation never use it (`Segments::TerrainElevation.
  eligible?`).
- **When.** After creation, after a visibility change that makes the course
  eligible (`Segments::ApplyTerrainElevationJob`), for the account's courses
  when it consents, and through the audited `/admin/jobs` backfill
  (`Segments::BackfillTerrainElevationJob`, `bin/rails
  segments:terrain_elevation`) for courses never tried or `failed`. A course cut
  from a workout already on `dem` is born `dem`; a copy inherits its source's
  `elevation_source`. A course turning private keeps the terrain figures it
  already has.
- **Sampling.** `Allure::Elevation::CourseTerrain` interpolates one location
  every `distance / 100` metres along the stored line, between 20 m and
  `ELEVATION_SAMPLE_METRES`, coarsened until it fits
  `ELEVATION_MAX_REQUESTS_PER_WORKOUT`; distances are rescaled to the stored
  course distance. The terrain must answer every location, otherwise the course
  keeps the device figures and is marked `unavailable`. The profile is filtered
  with the `dem` class (80 m window, 8 m threshold).
- **Columns.** `segments.elevation_source` (`device`/`dem`) and
  `segments.elevation_status` (`ready`/`unavailable`/`failed`, nil until
  tried). The figures are written in place; the course page shows the
  « Altitudes estimées (MNT) » badge on its chart.
- Existing course publications never change; a new publication carries the new
  `ascent`/`descent`/`average_grade`, and no new field leaves the instance.
- The settings page's privacy copy names the public-course rule.

## 10. Tests

- **Pure**: client (WebMock success, `null`, chunk limit, `INVALID_REQUEST`,
  5xx, 429, timeout, malformed, size cap), geometry chaining, sampler intervals
  and batches, profile runs and holes, track override.
- **Services and jobs**: enricher statuses and throttle, job retry/discard,
  reanalyzer source switch, importer follow-up enqueue.
- **Requests and views**: settings opt-in, per-workout source switch
  authorization and Turbo states, badge and partial state.
- **Courses**: eligibility, sampling bounds, status transitions, publication
  immutability.
- **Browser**: Playwright on `http://rails:3001` for the settings toggle, the
  automatic badge on a `no_elevation.gpx` import, and a source switch.
- Every change runs `dip rspec`, `dip rubocop` and `dip brakeman`; UI changes
  are verified in the browser.

## 11. Out of scope

- Publishing or federating the elevation source (no new Note tag, no snapshot
  field).
- Enriching remote notes or received remote courses (a local copy of one is a
  local course, §9).
- Filling interior holes of a partially recorded profile.
- Datum correction between DEM (orthometric) and GPS (ellipsoidal) elevations.
