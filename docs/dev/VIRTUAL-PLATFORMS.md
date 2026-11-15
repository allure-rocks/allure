# Virtual platforms contract

A workout recorded in a virtual system is identified as such: the recording
application is named on the workout, the sport is a virtual sport, the fictional
world is shown as the workout's place, and geocoding is never asked to name a
place the athlete never visited. Adding another provider is one catalogue
entry, not a code path.

## 1. Platform catalog

`lib/allure/virtual/platforms.rb` is the single source of truth; nothing else in
the application names a provider. Each entry is a value object
(`Allure::Virtual::Platform`) with:

| Field | Meaning |
|---|---|
| `key` | stable identifier (`"exr"`); never user-facing |
| `name` | display name; becomes `workouts.source` and the creator string |
| `fit_fingerprints` | partial `file_id` hashes; an entry matches when every declared field equals the file's value, so a provider may be pinned by manufacturer alone or by the full triple |
| `creator_aliases` | case-insensitive, token-matched creator names for formats that keep one (FIT `product_name`, GPX `<gpx creator>`) |
| `sport_slug` | the sport used only when the file itself carries no usable sport (`Workouts::SportResolver`) |
| `venues` | zero or more worlds, each with a name, an anchor (`longitude`, `latitude`) and a radius that contains every published route |
| `basemap` | optional: the world's published map image, its `[west, south, east, north]` rectangle, its background colour and its credit |

`Allure::Virtual::Platforms` exposes `all`, `fetch(key)`, `for_creator`,
`for_file_id`, `creator_for(file_id)` and `normalize`. `Allure::Fit::Parser`
resolves `Track#creator` through `creator_for` before the generic
manufacturer/product fallbacks (`FIT.md` §4), and fits a registered platform's
positions to its recorded distance (§7).

EXR entry: fingerprint `manufacturer: 255, product: 22, serial_number: 1234`,
aliases `exr`/`exrgame`, sport `rowing_virtual`, worlds **Boston**, **Bled**,
**Henley**, **EXR World** and **Long Beach** (EXR 1.56). World names are proper
nouns and are never translated. Radii are ~3 km (6 km for Boston and Long Beach,
whose courses spread further), derived from the observed start points with
margin; overlapping worlds resolve to the closest.

Zwift entry: fingerprints `manufacturer: 144` and `manufacturer: 260` (Zwift
writes no product name), aliases `zwift`, no sport fallback (the FIT
`sub_sport: virtual_activity` already detects `cycling_virtual` or
`running_virtual`), worlds **Watopia**, **Richmond**, **London**, **New York**,
**Innsbruck**, **Bologna**, **Yorkshire**, **Crit City**, **Makuri Islands**,
**France**, **Paris** and **Scotland**. The anchors and rectangles are the
bounding boxes of the MIT-licensed `zwift-data` package
(andipaetzold/zwift-data), reduced to a centre and a radius that contains the
whole map, except Paris: its current expansion map has no published rectangle
yet, so the rectangle is the previous one shifted by a quarter of its size north
and east, where the two maps register exactly (same scale, a 1024 px translation
of the 4096 px frame), and the anchor is its centre. Gravel Mountain (world id
12) has no published bounds yet and is left out rather than guessed. The current
Watopia map includes the north-west archipelago its races start on, and the
current Paris map includes Montmartre, Parc Monceau and the Madeleine.

## 2. World map images

A virtual world's recorded positions are fictional, so the ordinary basemap
draws them over open sea (Watopia, Crit City, Makuri Islands, France) or over a
real city that only roughly matches (London, Richmond, New York, Innsbruck,
Bologna, Yorkshire, Paris, Scotland). Each Zwift world therefore carries its own
map image, which replaces the basemap wherever the track is drawn.

- **Source.** The world maps ship under `public/virtual_worlds/zwift/`, with
  their provenance, their source digest and the `© Zwift` credit recorded in
  that directory's `README.md`. Each download is pinned by the SHA-256 of the
  file, because a provider may rewrite a map in place under the same name: a
  mismatch fails the task instead of silently shipping new artwork. The
  generated file is named after the pinned digest
  (`watopia-f4991742.webp`), so a new map always takes a new URL and no browser
  keeps the old one behind the production cache headers. Some source maps are
  stored with north to the right; the task turns them north-up. They are resized
  to 4096 px on the longest side and encoded as WebP. The application never
  downloads an image at runtime. The files are committed and ship in the
  production image; `bin/rails virtual:world_images` regenerates them from the
  pinned sources (development only, `WORLD=<key>` for one world), and a checkout
  without them draws the ordinary basemap. Updating a world is: review the new
  artwork, update the digest in the task and the image name in the catalogue,
  run the task, then re-render the owner route images drawn on that world — a
  one-off migration, as `20261107120000_rerender_virtual_world_route_images` did
  for Watopia and Paris.
- **Placement.** The image rectangle is the exact `bounds` of the MIT-licensed
  `zwift-data` package (`src/worlds.ts`), the same source as the venue anchors;
  the current Paris map is registered against the previous rectangle because
  `zwift-data` does not publish the new one yet (§1). The background colour is
  the world's own map background.
- **Selection.** `Allure::Virtual::Platforms.basemap_at(longitude:, latitude:,
  public_root:)` returns the world whose image rectangle contains the point, the
  closest anchor winning when rectangles overlap. A point just outside every
  rectangle but inside a world's radius still takes that world, so a track that
  leaves the published bounds draws on its world's map with the background
  colour around it. A world the catalogue does not know, or one whose image is
  not generated under `public_root`, keeps the ordinary basemap: recognition is
  a whitelist, never a guess. The caller must also require a virtual sport:
  Zwift's London rectangle covers real London, so geometry alone would claim a
  real ride there. `ApplicationHelper#virtual_basemap_for` applies both rules
  and honours the profile's own `basemap` setting. Nothing is stored on the
  workout or in a publication snapshot: the world is derived from the geometry
  every time, so the map also works on a received note and on a publication
  rendered by another instance.
- **Live map.** `shared/_map.html.erb` hands the image, its four corners, the
  background colour and the credit to the `map` controller, which builds a
  minimal style (a background layer plus an image layer) instead of fetching
  the OpenFreeMap document. No tile is requested. The credit is passed to the
  attribution control, because an image source carries none. The dark theme dims
  the same image with the raster paint properties and paints the world's dimmed
  background colour around it; there is no second image.
- **Route images.** `Workouts::MaplibreRouteImageRenderer` receives the same
  world as a data URL, so the headless renderer needs no network and no origin
  exception; the static renderer builds the same style through the shared
  `app/frontend/lib/virtual_world.js`. The Ruby fallbacks paint the world's
  colour (dimmed on the dark variant) instead of the application surface.
  `Workouts::RouteImage::VERSION` was bumped so the owner images regenerate.
- **Publications.** A new publication's route image uses the world image,
  exactly like the owner image, unless the profile disabled `basemap`. An
  existing publication keeps the image rendered at its identity: publication
  media are frozen snapshots (`PUBLISHING.md`).
- **Scope.** Workout pages (owner and reader), publications, received notes and
  route images. Course pages and the discover map still draw the ordinary
  basemap and are a later slice. EXR is not concerned: its courses sit on real
  water.

## 3. Virtual sports

`db/seeds.rb` sets `sports.virtual` (column added by `AddVirtualToSports`) on
`cycling_virtual`, `running_virtual` and `rowing_virtual`. The flag is per sport,
not per platform, so any provider whose FIT sport maps to a virtual sport
inherits the behavior.

A virtual sport means the recorded geography is rendered, not visited:

- `Workouts::Importer#enqueue_toponymy` does not enqueue geocoding, and
  `Workouts::VirtualVenueNamer` names the place instead;
- `Workouts::ToponymyEnricher#call` discards any existing toponymy and stops;
- `WorkoutToponymiesController#show` answers `status: unavailable` and destroys
  any legacy row rather than creating one; the chart hides that state;
- `Workouts::PlaceNamer` returns early, so a real-world assembly can never
  overwrite a venue name;
- `Workouts::BackfillPlacesJob.pending_scope` excludes virtual sports.

Legacy toponymy rows are cleared by the re-detection sweep (§6), by the
controller on the first poll, or by `SportChange` crossing the boundary.

FIT `fitness_equipment` with `indoor_rowing`/`indoor_cycling` also detects
`rowing_virtual`/`cycling_virtual`: the pair is unambiguous whatever app wrote
it, which covers ergometer files that previously used the import fallback.

## 4. Venue naming

`Workouts::VirtualVenueNamer` locates the platform from `workouts.source`,
matches the workout's `start_point` against the platform's worlds, and writes the
display list (`workouts.places`) and the indexable `workout_place_names` rows.
Both feed existing surfaces unchanged: the header pin line and the workout
list's place filter/autocomplete. An unknown world or an unregistered creator
leaves both lists empty rather than inventing a name. `#clear` empties them when
a workout leaves a virtual sport.

Places remain owner-only and never enter a publication snapshot or federation,
like every other place (`WORKOUT.md` §9.1).

## 5. Sport resolution

`Workouts::SportResolver` extracts the importer's resolution so the re-detection
sweep and the importer cannot drift. Order:

1. the file's own signal (`Allure::ActivityDetector`, FIT/GPX/TCX/KML);
2. the owner's generic-sport default for a detected catch-all;
3. the platform's `sport_slug` when the file carries none;
4. the caller's fallback sport, else `MissingSport`.

The first two stay reported as `detected`. Step 3 also reports `detected`: it
comes from the file's fingerprint, not from a user choice.

## 6. Facts reconciliation

The facts of a workout — recording device, re-detectable sport, virtual venue —
are one phase of the unified rebuild sweep, not a dedicated backfill
(`[devdoc:derivations]`). `Workouts::RebuildJob` parses the immutable original
once through `Workouts::OriginalTrack` and reconciles, fail-closed:

- `workouts.source` is filled when empty, or replaced when it is one of the
  names an older generation derived from a manufacturer code
  (`ImportDetection::SUPERSEDED_DEVICE_NAMES`); any other stored value is never
  overwritten;
- the sport is re-detected only when the import entry is still `detected`
  (`WORKOUT.md` §2.4) and differs; the change goes through
  `Workouts::SportChange`, so analysis, records, matching and the toponymy
  transition all follow, and the entry is rewritten as `detected`;
- a virtual sport (re-)names its venue and clears legacy toponymy.

`WorkoutImportEntry.sport_source` gains `manual` (migration
`ExtendWorkoutImportEntriesForManualSportChange`): every sport change made by
hand marks the entry, so a sweep never overwrites a human decision. A file that
cannot be parsed is reported through `Rails.error` and left pending.

The generation marker is `workouts.import_detection_version`
(`Workouts::ImportDetection::VERSION`): bump it when a provider, an alias or a
world changes; the sweep re-reads only the workouts whose stored generation is
older, without re-analysing their track. Entry points: the `/admin/jobs` rebuild
card (`AdminEvent#workouts_rebuild_enqueued`), the owner page `/settings/data`,
and `bin/rails workouts:rebuild` with optional `AFTER_ID=`.

## 7. Recorded distance

A virtual world's positions are drawn, not measured, and a platform may draw
them at a scale that differs from the recorded distance: one course can place
the boat at twice the distance rowed, and a world may drift by a few percent.
The ergometer's own distance, written in the FIT `lap` messages, is the
athlete's real effort and is authoritative. EXR writes no record `distance` and
no session `total_distance`.

`Allure::Fit::Parser` passes the segments of a file whose `file_id` matches a
registered platform through `Allure::Virtual::DistanceCalibration`, which is
pure and runs before the analyzer:

1. the analyzer's own outlier filter (`Allure::Gpx::Outliers`, `WORKOUT.md`
   §6.9) runs first, because a platform often snaps its last record to the
   finish line and the analyzer would otherwise drop that jump with the distance
   it carries;
2. the ratio is the summed lap distance over the drawn horizontal distance;
3. every point keeps its time and signals and is moved along its own recording
   segment to its cumulative distance times the ratio, so the map follows the
   course (a 2 000 m race keeps its outbound leg); beyond the drawn end, a
   segment extends along its last direction;
4. resampling cuts the corners of a quantized zigzag, so a last pass scales every
   step vector by the small remaining ratio, which makes the length exact.

Distance, speed, pace, splits, best efforts, detected laps and segment efforts
therefore all agree with the recorded distance. The calibration is fail-closed —
the segments are returned unchanged — when there is no lap distance, when the
laps cover less than 90 % of the recording span, when the ratio falls outside
0.25–4, or when the drawn distance already matches. A device outside the
catalogue is never calibrated, and neither is a positionless recording: it has
no drawn course, and its distance already comes from the device
(`[devdoc:no-gps]`). The change is analyzer version 10
(`[devdoc:elevation]`), so the rebuild sweep reanalyzes existing workouts and
`Workouts::Reanalyzer` re-renders the route image of those whose geometry moved.

### 7.1 Teleports

A virtual platform can move the athlete without moving them: a video route that
ends by returning the rider to its start, a world change, a respawn. The recorded
positions then jump kilometres in one second while the device's own cumulative
distance keeps advancing normally. A single recording segment would draw a
straight line across the map and measure a speed no sport reaches.

`Allure::Virtual::Teleports` detects such a step: at least 200 m, and either an
implied speed above 216 km/h or ten times the distance the device recorded for
that step (its own speed reading stands in when the file records no distance, as
EXR does). `Allure::Fit::Parser` closes the recording segment there, exactly as a
timer stop does, so the jump is never drawn and never measured. The calibration
of §7 then fits the split segments to the recorded lap distance as before. The
change is analyzer version 15; an ordinary device is never split this way.

The jump is not ground, so it is never elevation either. The analyzer sums each
segment's ascent and descent, which leaves the jump out; the smart-lap climb and
descent detectors (`SMART-LAPS.md` §4.3) build their profile over one continuous
run of ground at a time and break it at a boundary whose positions jump 200 m or
more. A climb therefore never spans a teleport — before that rule, a video route
returning to its start produced a phantom climb of the whole jump, which held the
biggest-climb record. A boundary that is only a pause keeps the profile
continuous, so a climb that spans a pause stays one climb.

## 8. Presentation

A virtual platform's speed is a game output: the draft, the gradient, the bike,
the rider's weight and the course all feed it, while the watts are the athlete's
own effort. A virtual ride therefore leads with average power when the recording
carries it. `Sport#power_led?` — `virtual?` and a `speed` pace/speed display,
which is `cycling_virtual` alone in the catalog — puts average power in the
third summary tile in place of the speed, on the activity card, and as the
chart's default secondary line; the chart keeps its own stored selector choice,
apart from the other charts'.

The fourth tile stays the elevation gain, which a rendered course still asks of
the rider and a smart trainer still simulates. Speed keeps its place in the
secondary metrics, the analysis tables and the chart selector. A virtual run
keeps its pace, and a virtual row keeps its fixed 500 m basis with power as its
fourth tile. A publication whose profile withholds power, and the credited
metric set (which has no power), fall back to speed.

The map follows the same rule: a power-led ride offers *Puissance* first in its
colour-by selector, the power ramp spans the bulk of its readings (the 2nd to
98th percentile, each colour stop averaging its own slice of the route), and a
legend names the ramp's two ends. The analysis tables read their effort column
as average power with the speed as a quiet second line, and each split carries
its own average power (the same sample mean as the laps).

Records, best efforts and the publication snapshot are untouched: the
power-duration curve, and any watts-per-kilogram figure that would need a stored
body weight, are later contracts.

## 9. Deliberately unchanged

- Segment matching and automatic loop creation still run for virtual workouts:
  a rendered course is still a recognizable route.
- Elevation profiles are untouched, and maps and route images draw the
  calibrated positions on the world's own map image (§2).
- Record markers, best efforts and the publication snapshot are untouched.
- Circuits (one name per course inside a world) are not modeled yet; the venue
  catalog is the natural place for them once a reference geometry exists. Until
  then an owner can name a course once by creating a route from a workout
  (`SEGMENTS.md`).

## 10. Testing

- `spec/lib/allure/virtual/platforms_spec.rb` proves fingerprint, alias and
  venue matching, that a second provider is pure catalogue data, and the Zwift
  entry (both manufacturers, Watopia, Richmond and both Paris circuits, no sport
  fallback, an unnamed point, the world map lookup, an anchor centred on its
  rectangle, a shipped image per world with no orphan file, and each image's
  proportions matching its rectangle).
- `spec/lib/allure/virtual/basemap_spec.rb` proves the rectangle test, the
  MapLibre corner order, the public path, the dark colour and the refusals.
- `spec/lib/allure/virtual/distance_calibration_spec.rb` proves the doubled,
  out-and-back, too-short, finish-snap, stationary-start and multi-segment cases
  and every fail-closed condition; `spec/lib/allure/fit/parser_spec.rb` proves
  the parser calibrates a registered platform only.
- `spec/services/workouts/virtual_venue_namer_spec.rb` proves naming, clearing,
  unknown worlds and the non-virtual guard.
- `spec/services/workouts/sport_resolver_spec.rb` proves the resolution order.
- `spec/db/virtual_world_route_images_migration_spec.rb` proves that a world map
  change invalidates only the virtual recordings drawn on the worlds whose
  artwork changed, queues one low-priority sweep, enqueues nothing on a fresh
  installation, and fails visibly when the queue is unreachable.
- `spec/jobs/workouts/rebuild_job_spec.rb` proves the facts reconciliation rules,
  the manual guard, the single parse and the unreadable-file path;
  `backfill_rebuild_job_spec.rb` proves the cursor and the two markers.
- Importer, toponymy controller, enricher, place-namer and admin specs prove the
  virtual guards and the audited action.
