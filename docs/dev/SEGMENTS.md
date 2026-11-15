# Segments contract

User-defined segments, reusable routes, detected loops, matched efforts,
splits, personal bests and leaderboards. `SEGMENTS-FEDERATION.md` covers the
course-only federation of a segment; `SMART-LAPS.md` covers the derived laps
shown beside the efforts; `BEST-EFFORTS.md` covers the standard-distance
efforts and records. `WORKOUT.md` covers the source workout and its metrics.

## 1. Vocabulary

- **Segment** — a reusable course selected from one of the owner's workouts,
  matched against the owner's other workouts. It is never owned by a workout.
- **Route** — a segment created from a complete workout track, matched end to
  end.
- **Loop** — a segment detected from a repeated circuit inside one workout,
  owned by the account and reused by every later workout closing the same
  circuit.
- **Effort** — one matched traversal of a course by one workout, with its
  elapsed time, metrics and match quality.
- **Split** — a kilometre or mile slice of one workout, computed on demand.
- **Personal best** — the fastest effort of one athlete on one course and
  sport.
- **Board** — the ranking of the efforts a reader may see on one course.

A recording segment (`TrackSegment`) is a different thing: one contiguous run
between pauses, owned by a workout. The codebase keeps the two apart by name.

## 2. Decisions

### 2.1 One table, three kinds

A single `segments` table carries `kind` ∈ `segment`, `route`, `loop`. The
matcher, the effort table, the leaderboard queries, the visibility rules and
the UI are identical for all three. A route is a segment matched end to end; a
loop is a segment sourced from a detected circuit. Separate tables would
triple the code with no semantic gain. A file-recorded lap is a separate `laps`
row, shown in preference to loop efforts.

### 2.2 Geometry first, deterministic signature, no neural embeddings

Segment matching must return **entry and exit indices** so an elapsed time can
be computed. An embedding returns a similarity score, not indices; a
leaderboard cannot be built from a cosine distance. At self-hosted scale, a
PostGIS `ST_DWithin` prefilter on the existing GiST indexes plus exact
verification is faster to build, exactly explainable, and adds no
infrastructure. A neural encoder would break determinism, offline processing,
and the no-external-service rule.

The locked approach:

1. **Locality filter** — PostGIS `ST_DWithin` against the existing GiST
   indexes.
2. **Shape filter** — `Allure::Geometry::ShapeSignature`, a deterministic
   64-dimension descriptor computed in pure Ruby: arc-length resampling to 64
   equidistant points, then a normalized turning-angle profile. Stored as
   `real[]`.
3. **Verdict** — banded discrete Fréchet distance, geodesic, computed through
   `Allure::Gpx::Geo.horizontal_distance`.

Fréchet, not Hausdorff: Fréchet respects point ordering, so a reversed
traversal fails naturally and no separate bearing check is required.

> **Trap to keep in the document and in a spec.** The turning-angle signature is
> invariant under rotation and translation. Two identically shaped loops in two
> different cities produce the same signature. The signature is **never used
> alone** — it is only a fast rejection test applied *after* the locality
> filter.

**Extension point.** `ShapeSignature.compute(coordinates) -> Array<Float>` is
the stable interface. If approximate nearest-neighbour search ever becomes
necessary, `signature` becomes `vector(64)` with an HNSW index and nothing else
changes. The cost is recorded: `imresamu/postgis:18-3.6` does not ship
`pgvector`, so this requires building and maintaining a custom multi-arch
database image. Do not take that cost without a measured need.

### 2.3 Units and identifiers

- Persisted metric values are SI, exactly as `WORKOUT.md` §2.1: metres,
  seconds, metres per second, seconds per kilometre.
- Public identifiers are ShortUUID-encoded UUIDs through `HasShortId`. Integer
  primary keys never appear in a URL, a payload or a DOM attribute.
- Conversion to the viewer's unit system happens only at the presentation
  boundary, reusing the existing formatting helpers.

### 2.4 An effort may not cross a recording gap

An effort whose interval would span a `track_segment` boundary is **rejected**.
No effort row is created. A recording pause inside a segment makes the elapsed
time meaningless, and a silently wrong time on a leaderboard is worse than a
missing one. The workout view explains why a candidate segment produced no
effort, so this does not become an unexplained absence.

### 2.5 Leaderboard aliases

- `Allure::Leaderboard::Alias.for(user_id:, segment_id:)` derives a pseudonym
  from `HMAC-SHA256` over `(user_id, segment_id)` with a key derived from
  `secret_key_base`, projected onto a bilingual word list plus an integer:
  `Grimpeur 7` / `Climber 7`.
- The alias is **stable within one leaderboard and unlinkable across
  segments**. A user can follow their own progression on a segment; an observer
  cannot join two segments into a location history.
- Collisions within one segment are resolved deterministically by appending a
  discriminating digit, never by a random draw.
- An anonymous row **never** emits: `user_id`, ShortUUID, profile path, avatar
  URL, DOM data attribute carrying an identity, or an exact `started_at`. The
  displayed date is **coarsened to the month**.

Residual risks, to be stated in the UI copy and not only here:

- The alias is irreversible for the public but **not** for the instance
  administrator, who has database access.
- On a small instance, an alias is close to an identity by elimination.
- Pseudonymised data remains personal data; an alias is a mitigation, not a
  lawful basis.

### 2.6 ActivityPub contract for anonymity

> An effort marked anonymous is **purely local**. It is never serialized to
> ActivityPub and never placed in an ActivityPub collection.

This is a protocol fact, not a preference. ActivityStreams 2.0 requires
`attributedTo` to name an actor URI, and HTTP Signatures prove possession of a
key and therefore an actor. A shared pseudonymous actor breaks signature
verification; omitting attribution makes remote servers reject or fail to
render the object. There is no anonymous authorship in the fediverse.

`SEGMENTS-FEDERATION.md` strengthens this into an contract-wide property: its
course-only distribution never serializes an effort at all, anonymous or not.
Anonymity is resolved server-side at render time, on local HTML only.

### 2.7 Matching parameters

| Parameter | Default | Range | Meaning |
|---|---|---|---|
| `match_tolerance_meters` | 25 (segment, loop), 100 (route) | 5–100 | per course; maximum Fréchet deviation, and the bound on the entry/exit search |
| anchor spacing | 10 m | fixed | segment resampling step for matching |
| signature dimensions | 64 | fixed | `ShapeSignature` output cardinality |
| signature L1 threshold | 16.0 | fixed | maximum pre-Fréchet signature distance |
| length window | 0.8–1.3 × | fixed | accepted traversed length ratio |
| `min_loop_distance` | 400 m | fixed | shortest detectable loop |
| loop closure radius | 30 m | fixed | return-to-start radius |
| minimum laps | 2 | fixed | below this, the workout is not lapped |
| `matcher_version` | integer | — | bumped when any of the above changes |

Changing any locked value bumps `matcher_version`, which invalidates and
recomputes stored efforts. Existing efforts are never silently reinterpreted
under new parameters.

A **route** defaults to `100 m` (`Segments::Creator::ROUTE_MATCH_TOLERANCE_METERS`),
not 25 m: its endpoints are the recording's own start and stop, where the
artefacts and the consumer GPS drift are largest. Segments and received courses
keep 25 m, because they are compared on a selected corridor and feed
leaderboards where a wider corridor would merge parallel roads; detected loops
keep it too, so adjacent circuits stay distinct. The route form, the
recurring-route detector and the demo seed use the route default; an owner can
still choose any value in the 5–100 m range per route.

**Calibration note, measured on real repeated-route data.** Four recordings of
one 6.7 km running loop by the same user were matched pairwise, each in turn
supplying the canonical geometry:

- Taking a *whole raw workout* as the segment makes matching depend on which
  recording was chosen, because the start and stop artefacts of that particular
  recording become part of the reference geometry. Observed endpoint offsets
  between recordings reached 50 m.
- Taking a *selected portion*, dropping roughly 200 m at each end, removes that
  dependency: every recording then matches from every canonical choice.
- Genuinely different routes stayed rejected throughout, with Fréchet distances
  around 2 200 m against a 25 m threshold, so nothing here weakens the filter.

This is the practical argument for creating segments from an explicit map or
chart selection rather than from a whole track, and for
`match_tolerance_meters` remaining per-segment and user-adjustable: one pair in
the sample sat at 25.7 m, just above the default.

### 2.8 Naming

The word "segment" was already taken by the recording segment. The recording
concept was renamed rather than the new one: `WorkoutSegment` became
`TrackSegment`, `workout_segments` became `track_segments`, and
`Workout#segments` became `Workout#track_segments`. `TrackSegment` is the
GPX-native name — `<trkseg>` is literally a track segment — and it lines up
with the `/workouts/:id/track` endpoint.

**`Workout#segments` no longer exists.** A `Segment` is not owned by a workout,
so no association reclaims that name. A workout reaches this feature only
through `Workout#segment_efforts`.

`Allure::Gpx::Segment`, `Allure::Gpx::Track#segments`,
`Analyzer::SegmentMetrics`, and the `segments:` keyword arguments of
`ChartSeries` and `RouteImageRenderer` are deliberately **not** renamed. They
live inside the `Gpx` namespace, where "segment" means `<trkseg>` by definition.

## 3. Data model

The full column list is `db/schema.rb`; this section fixes the structural
groups and the invariants.

### 3.1 `segments`

| Group | Columns |
|---|---|
| Identity | `uuid`, `user_id`, `sport_id` (nullable = all sports), `kind` (`segment`, `route`, `loop`) |
| Description | `name` (1–120), `description` (≤ 2 000) |
| Geometry | `geom:geography(LineString,4326)`, `start_point`, `end_point`, `bounds:float[]`, `distance`, `signature:real[]` |
| Elevation | `ascent`, `descent`, `min_elevation`, `max_elevation`, `average_grade`, `elevation_profile:jsonb`, `elevation_source`, `elevation_status` |
| Matching | `match_tolerance_meters` (5–100), `matcher_version` |
| Visibility | `visibility` (`private`, `followers_only`, `public`), `active`, `privacy_zone_acknowledged_at` |
| Provenance | `source_workout_id`, `source_start_index`, `source_end_index`, `remote_segment_id`, `renamed_at` |
| Presentation | `place_name`, `place_status`, `place_geocoded_at`, `route_image_version` |
| Counters | `efforts_count`, `athletes_count` |

Indexes: unique `uuid`; `(user_id, kind)`; `(visibility, kind)`;
`(place_status, id)`; unique `(remote_segment_id, user_id)` where the remote id
is present; GiST on `geom`, `start_point` and `end_point`.

Database checks: `kind`, `visibility` and `place_status` value sets;
`distance > 0`; `cardinality(bounds) = 4`; `cardinality(signature) = 64`;
`match_tolerance_meters BETWEEN 5 AND 100`; `st_npoints(geom::geometry) >= 2`;
name and description length. Model validations mirror the checks and do not
replace them.

`elevation_profile` is a frozen course profile, an array of `{ "d", "ele" }` up
to 240 points with distance rebased to 0. `NULL` means not built, `[]` means
built without usable elevation. It is written once at creation (or by the
backfill sweep), replaced once by the terrain profile (`[devdoc:elevation]`),
and never federated. `average_grade` is signed: the net change from the first
to the last valid elevation over the distance, so a descent reads negative; a
reversed copy negates it.

The board follows `visibility`; there is no separate board audience. The
publishing profile's former `segment` setting is retired: the route setting is
the consent, and the per-segment opt-out stays. Frozen snapshots that still
carry `segment` are accepted and ignored.

### 3.2 `segment_efforts`

| Group | Columns |
|---|---|
| Identity | `uuid`, `segment_id`, `workout_id`, `user_id`, `sport_id`, `occurrence_index` |
| Time | `started_at`, `elapsed_time`, `moving_time` |
| Metrics | `distance`, `ascent`, `descent`, `average_speed`, `average_pace`, `average_heart_rate`, `max_heart_rate`, `average_cadence`, `average_power`, `max_power`, `grade_adjusted_pace` |
| Position | `start_offset_meters`, `start_point_index`, `end_point_index` |
| Match | `deviation_meters`, `matcher_version` |
| Board | `personal_best`, `anonymous` |

Indexes: unique `uuid`; unique `(segment_id, workout_id, occurrence_index)`;
`(segment_id, elapsed_time)` and `(segment_id, sport_id, elapsed_time)` for
per-sport ordering; partial `(segment_id, user_id, sport_id) WHERE
personal_best`; `(workout_id)`; `(user_id, segment_id, elapsed_time)`.

Checks: `elapsed_time > 0`; `moving_time BETWEEN 0 AND elapsed_time`;
`occurrence_index >= 0`; `end_point_index > start_point_index`; non-negative
distance, ascent, descent and speed.

An effort is deleted with its workout and with its segment. It is a derived
record and is always reconstructible by re-running the matcher.

### 3.3 `segment_opt_outs`

| Column | Notes |
|---|---|
| `segment_id` | not null, `ON DELETE CASCADE` |
| `user_id` | not null, `ON DELETE CASCADE` |
| timestamps | Rails timestamps |

Unique `(segment_id, user_id)`, plus `user_id` for the athlete's own joins. A
row is an exclusion: the athlete is ranked on that segment unless they hold
one. There is no implicit participant, the owner holds exclusions like anyone
else, and excluding a course before running it is allowed. Nothing is
recomputed when a row is written: `Segments::Listing` reads the exclusion on
every board query.

### 3.4 Splits

**No table.** Splits are computed on demand by `Allure::Gpx::Splits` from the
existing per-point jsonb, in the viewer's unit system. They are cheap, always
consistent with the stored points, and require no invalidation.

### 3.5 `route_suggestions`

Owner-only bookkeeping, never a course and never published:

| Column | Meaning |
|---|---|
| `user_id` | the owner |
| `sport_id` | the sport of the comparison; routes inherit one |
| `reference_workout_id` | the recording the route form is built from; nullified when deleted, and the newest remaining member takes its place |
| `segment_id` | the route saved from the suggestion, once accepted |
| `status` | `pending`, `dismissed`, `accepted` |

`route_suggestion_workouts` names the recordings of one suggestion; a recording
belongs to one suggestion only (unique `workout_id`). Deleting a recording
drops its membership, and a suggestion left without a member disappears.

### 3.6 Changes to existing tables

- `segment_efforts.listed` was dropped when eligibility moved to the read path;
  `segment_participations` was replaced by `segment_opt_outs`.
- `users.leaderboard_participation` was dropped when participation became per
  segment.
- `users.leaderboard_category` is the self-declared category behind the board's
  category view.
- The publishing profile's `segment` setting is retired.

## 4. Algorithms

### 4.1 Candidate selection

Both directions are served by the GiST indexes that already exist.

Workout to segments, at match time:

```sql
SELECT s.*
FROM segments s
WHERE s.active
  AND s.distance <= :workout_distance
  AND (s.sport_id IS NULL OR s.sport_id = :sport_id)
  AND EXISTS (
    SELECT 1 FROM track_segments ws
    WHERE ws.workout_id = :workout_id
      AND ST_DWithin(ws.geom, s.start_point, s.match_tolerance_meters)
  )
  AND EXISTS (
    SELECT 1 FROM track_segments ws
    WHERE ws.workout_id = :workout_id
      AND ST_DWithin(ws.geom, s.end_point, s.match_tolerance_meters)
  )
```

Segment to workouts, at backfill time, mirrors the same predicate with the
workout set as the scanned relation. The candidate set is then narrowed by an
L1 distance between shape signatures before any Fréchet computation runs.

### 4.2 Traversal detection

Pure Ruby, operating on values only.

1. **Flatten.** Iterate `track_segments` in `position` order and build one
   global stream of points carrying absolute time, cumulative distance across
   segments (the `ChartSeries` `distance_offset` pattern), coordinates,
   elevation and sensor values. Record the `track_segment` boundary at each
   index.
2. **Anchor.** Resample the segment geometry at 10 m spacing into `A[0..M]`.
3. **Bracket.** Collect entry candidates as local minima of the distance to
   `A[0]` under tolerance, and exit candidates likewise against `A[M]`.
4. **Verify.** For every ordered pair whose traversed length falls in
   `[0.8, 1.3] × segment.distance`, compute the banded discrete Fréchet
   distance between `A` and the track slice. Accept when it is at or below
   `match_tolerance_meters`. Ordering is enforced by Fréchet, so a reversed
   traversal is rejected without an explicit direction test.
5. **Reject gap-spanning intervals.** If the slice crosses a `track_segment`
   boundary, discard it per §2.4.
6. **Refine.** Project `A[0]` and `A[M]` onto the polyline and interpolate time
   linearly between the bracketing points, so `elapsed_time` is not quantized
   to the sampling rate.
7. **Select.** Sort valid traversals by start index and greedily keep
   non-overlapping ones, numbering them `occurrence_index` 0..N.

Step 7 is where laps fall out for free: repeated traversals of the same
geometry within one workout are exactly repeated occurrences.

**Complexity.** For a 2 km segment, `M ≈ 200` and the candidate slice holds
roughly 400 points. Banded Fréchet visits far fewer than 80 000 cells. This is
milliseconds per candidate, and the candidate set on a self-hosted instance is
typically under 50.

### 4.3 Loop detection and laps

`Allure::Geometry::LoopCandidates` searches for interior circuits independently
inside each recording segment, so an approach and return do not belong to the
loop. Earth-centred spatial cells (30 m) index anchors spaced at least 10 m
apart, capped at 16 per cell. A visit keeps the nearest source point until the
track exits the closure radius. Consecutive visits at least 400 m apart propose
a circuit; four length groups per anchor merge lengths within 10%. Only the
32 highest-ranked groups per recording segment undergo the reverse-Fréchet
out-and-back guard. Repeated groups rank before single closures, then by
estimated covered distance, shortest circuit and earliest start. This is a
bounded heuristic, not an exhaustive search of all point pairs.

`Segments::LoopDetection` takes at most 32 candidates across recording segments
(repeated groups first, estimated coverage then earliest start), and validates
each with the standard matcher, using an existing similar loop when available
or an unsaved geometry preview. Failed candidates do not create database rows
and do not stop the search. A new circuit needs at least two complete,
non-overlapping, same-direction traversals. Each traversal stays within one
recording segment; complete tours may occur in separate segments. Incomplete
tours, the approach and the return are not padded into complete tours. Loop
matching uses distance-windowed endpoint pairs, not their Cartesian product;
its length and shape verdicts remain unchanged. Candidate ranking uses the
matcher's `summary_only:` mode: the exact interpolated boundaries, valid
duration and distance, without computing elevation, sensors or GAP for
discarded candidates. Full effort metrics are computed for the retained loop.

Known loops are recognized independently of geometric discovery, through
`Segments::CandidateQuery.for_loop_workout`: active loops of the owner only,
within the matcher's minimum distance window and with both endpoints near one
recording segment. Sport is ignored, as for loop reuse. Standard matching
against the stored geometry requires only **one** complete same-direction
traversal for a known loop; partial, reversed or recording-gap-spanning
traversals are still refused. A single recognized effort is persisted and
projected as a detected lap, preserving the loop's identity and history.
Recognition is independent of whether discovery finds any candidate at all.
Each known geometry is matched once per run, and discovery can still propose a
new repeated circuit alongside known-loop results.

One circuit is retained per workout. Among candidates covering at least 99% of
the largest validated cumulative distance, prefer a loop the owner renamed
(`segments.renamed_at`: its name is the identity the owner chose), then the
most complete tours (the elementary circuit rather than a multiple-tour
circuit), then coverage, then the earliest matched start and oldest existing
loop. With no qualifying candidate, no loop effort is kept. All source indexes
refer to the original flattened point stream.

A persisted `loop` segment is owned by the workout owner, is always `private`,
and carries the `source_workout_id` of the first workout that detected it. It
belongs to the account, not to a single workout: when another workout of the
same owner closes the same circuit — compared as point sets by
`Allure::Geometry::Hausdorff` within the segment's `match_tolerance_meters`,
whatever the sport — `Segments::LoopReuse` elects the owner-renamed loop when
one matches and otherwise the oldest similar segment, and the workout attaches
its efforts to it instead of creating a second segment. One circuit therefore
keeps one name, one owner image and one effort history; the sport widens to
"all sports" when the reused recordings disagree.
`Segments::BackfillLoopReuseJob` re-runs the matching for every positioned
recording whose detection/reuse generation is old, including recordings with
no detected loop, so new discovery also reaches previously missed circuits and
legacy duplicates converge onto the renamed loop when one exists, otherwise
onto the oldest segment (`[devdoc:derivations]`). A loop the owner renamed is
never a disposable derived row: the sweep never removes it, and only the owner
deletes it. The rename mark is only ever set by an explicit rename; a stored
name cannot tell an auto-generated "<title> loop" from an owner's choice.

A geometric `loop` is distinct from a **file-recorded lap** (a FIT `lap`
message or a GPX `<lap>` element). Recorded laps are persisted as a separate
`laps` concept and shown in preference on the workout page; a `loop` is the
fallback when the source file recorded no laps.

Smart laps generalise that fallback: `SMART-LAPS.md` projects loop and route
efforts, recording pauses, and detected climbs into `detected_laps`, rendered
owner-only beside recorded laps and splits. A detected lap is not a segment and
never enters the shareable, leaderboard or federation matrix.

### 4.4 Routes

A route is created explicitly by the user from a complete workout track
("save as route"). Matching a workout to a route additionally requires:

- workout start within tolerance of `route.start_point`;
- workout end within tolerance of `route.end_point`;
- total length within ±10 % of `route.distance`;

before the standard Fréchet verification runs.

`Segments::BackfillSegmentJob` attaches past workouts retroactively, so saving
a route immediately produces its full history. Automatic *suggestion* of a
recurring route is §4.7. Automatic *creation* is out of scope.

### 4.5 Splits

`Allure::Gpx::Splits.new(segments:, unit:, workout_started_at:)` walks the same
flattened stream and closes a split every 1 000 m or 1 609.344 m, interpolating
the crossing point exactly as §4.2 step 6 does. The trailing partial split is
returned and flagged, never padded or discarded silently.

### 4.6 Personal bests

`personal_best` is maintained on `after_commit`. For each
`(segment_id, user_id, sport_id)`, the effort with the smallest `elapsed_time`
wins; ties break on the earlier `started_at`. A multi-sport segment therefore
keeps one best per athlete and sport. The partial index makes the lookup a
single row read. Every athlete with an effort on the segment is recomputed, not
only its creator: a shared course is matched against other accounts' workouts.
The second and third personal places are not stored; `Segments::PersonalPlaces`
derives them on read with the same order, owner-only.

Leaderboards partition on the same key: the owner and shared views render one
ranking section per sport, in catalog order, so a `NULL` sport segment reads as
several individual boards named `segment (sport)`.

### 4.7 Recurring-route suggestions

Allure suggests saving a recurring route; it never creates one. The verdict is
the route matcher itself (§4.2, kind `route`): a recording is compared with the
owner's other positioned recordings of the same sport, and a suggestion is
created only when at least `MIN_OCCURRENCES = 3` recordings would be attached
to the route saved from one of them. The comparison uses an unsaved preview
route built exactly like `Segments::Creator` builds one — the whole flattened
stream, its measured length, its shape signature — and the same ±10 % length
window, endpoint tolerance (the route default, 100 m) and Fréchet verdict. An
existing route is judged at the larger of its own tolerance and the route
default, so a recording that resembles a route already saved at 25 m is not
suggested as a new one. A reversed track, another sport, a recording already
covered by a route, or a recording belonging to another account never matches.

Detection runs after a non-bulk import (`Segments::SuggestRouteJob`) and, for
the existing history, through the audited `Segments::RouteSuggestionSweepJob`
(`/admin/jobs`, `/settings/data`, and the end of a bulk import batch). The sweep
walks one account from its newest recording to its oldest, so the suggestion's
reference — the geometry the route form uses — is the most recent occurrence.
`workouts.route_suggestion_version` marks the recordings the detector has
examined (`[devdoc:derivations]`).

The banner appears on the owner's page of every member of a pending suggestion
(`DESIGN.md` §10.18): « Enregistrer en itinéraire » opens the ordinary route
form, prefilled with a name built from the departure and arrival places, and
states that the group's recordings will be attached; saving the route accepts
the suggestion. « Ignorer » dismisses it for good, and later repeats of the
same circuit join it silently. A route saved from another recording leaves the
suggestion pending until the reference carries the route effort. Deleting an
accepted route does not bring the suggestion back: the owner's decision stands.
A suggestion never enters a publication snapshot, a federation payload, the
REST API, MCP or the data export.

## 5. Visibility, eligibility and privacy

### 5.1 Segment geometry

A segment's geometry is exposed at its own `visibility` level. Publishing a
segment publishes a route corridor. It does not publish the owner's tracks, but
it does publish a line on a map that the owner chose.

### 5.2 Effort eligibility

The board follows its reader, not the course: the course `visibility` only
decides who sees the course, and each effort appears to the readers of its own
publication.

```
effort shown to viewer  ⟸  segment.visibility ≠ private
                        ∧  segment.active
                        ∧  viewer may see the segment (Segment.visible_to)
                        ∧  the workout has an active publication the viewer
                           may read (WorkoutPublication.visible_to — the
                           feed's rule) whose frozen profile snapshot shares
                           the route (`route: true`, not redacted)
                        ∧  effort.user holds no `segment_opt_outs` row
                        ∧  no active privacy zone of the effort's owner
                           intersects the segment corridor
```

Eligibility is **derived on read** for one viewer by `Segments::Listing`
(`for_segment(segment, viewer:, scope:)`), a SQL scope built from INNER JOIN,
IN and NOT EXISTS clauses: there is no stored snapshot, no refresh job, and no
trigger on publication, visibility, follow, exclusion or privacy-zone commits.
Two viewers may read two different boards, and a rank reads « among the
athletes you can see ».

Every participant count shown on a shared course follows the same rule: the
course page's Participants tile, the `Mon rang` denominator and the `Découvrir`
popup count the distinct athletes of the viewer's own board
(`Listing.participants_count`/`participants_counts`), never an effort the board
would hide — an unpublished one included. A private course, read by its owner
alone, counts every recorded effort (`Segment#participants_count`). The stored
`athletes_count` is never displayed; it only orders the `Découvrir` cap, which
names no count.

Showing a passage to a reader who can already read its publication discloses
nothing new: the publication shows that reader the route and the time. The
route condition is the other half of that argument — a publication that hides
its route must not be revealed by a course crossing it. A public publication
therefore reaches every member who sees the course, a followers publication the
athlete's accepted followers (while restricted federation is enabled), and
future audiences follow without change (`PUBLISHING.md`).

The check is **fail-closed by construction**. A missing publication, a route
not shared, an unreadable exclusion or zone, and an absent viewer all exclude
the effort. `private` matches nothing, which keeps routes and loops — always
private — off every board.

The publishing profile's former `segment` setting is retired: the route setting
is the consent, and the per-segment opt-out stays. Frozen snapshots that still
carry `segment` are accepted and ignored, so an athlete who had turned it off
appears again wherever their route is shared.

The board has two views (`?board=`): **everyone** the viewer sees, and
**following** — the accounts the viewer follows plus the viewer
(`Listing.following_user_ids`). `Segments::Reach` gives the athlete's own line
on the course page: who sees them (`public`, `followers`) or the one reason
nobody does (`opted_out`, `zoned`, `route_hidden`, `unpublished`).

### 5.3 Privacy zones

A shared leaderboard publishes two different things: the segment geometry,
which the owner chose to publish, and the fact that user X traversed it at time
T, which is a location-history disclosure about a third party. That is why the
board is gated on the publication's shared route and on the athlete's active
privacy zones. A zone created after an effort does not retroactively rewrite a
stored row; the read-time scope excludes the effort while the zone is active.

### 5.4 Visibility matrix

The course `visibility` decides who sees the course — its page, geometry,
listing, discover map and course publication — and is a gate for its board:
nobody reads the board of a course they cannot see. Who appears on the board is
the §5.2 reader-relative rule.

| `visibility` | Course viewer | Who that viewer sees on the board |
|---|---|---|
| `private` | owner only | nobody: no board |
| `followers_only` | accepted followers of the course owner | athletes whose publication sharing the route the viewer may read |
| `public` | any signed-in account | the same rule |

An anonymous browser is never a viewer: every browser surface requires a
session and a visitor is redirected to sign-in (`ACCESS.md`).

An effort a viewer may not read stays invisible to them, the segment owner
included. Names follow §5.5. Every course the viewer may see — the readable
shared ones and their own, private ones included — is listed in the Segments
index, one kind at a time, the viewer's own badged; the `Découvrir` page
(`GET /segments?kind=discover`) is the map alone, fed by
`GET /segments/discover_map?bbox=…`, with no filter. Creation starts from the
index's `Nouveau segment` / `Nouvel itinéraire` action at `GET /segments/new`
(`SegmentSourcesController`, `?kind=route` for a route): the owner picks the
source among their own positioned recordings (`workouts.positioned`, latest
first as a shortcut, a `place` filter through `Workouts::ListQuery`), then
selects on `/workouts/:id/segments/new` or `/workouts/:id/routes/new`.

The index is a list, not a card grid (`DESIGN.md` §20.6): one row per course
and sport — an all-sports course has one row per sport it was run in (on the
board the viewer reads, or by the viewer), named `Nom (Sport)`, and a single
« Tous les sports » row while nobody ran it — with its glyph (the line
simplified in SQL by `Segments::ListQuery` and fitted by
`Allure::Segments::Thumbnail`), name, nearby place, sport, distance, ascent,
average grade, mini elevation profile (`Allure::Segments::Sparkline` over the
stored `elevation_profile`), the board's record and the viewer's own best time.
The record is the leader of the row sport's board the viewer reads
(`Segments::Podiums`, keyed by course and sport) under the §5.5 alias rules; a
private course, a route or a loop has no board and no record column. The best
time is the viewer's fastest effort in the row's sport, with their standing
when they rank. A sport filter keeps the rows of the chosen sports and the
all-sports courses nobody ran yet; the sort (newest, name, distance, ascent,
grade, record, best) puts missing values last both ways, and the record and
best sorts read the row's sport, under `Segments::Listing`. The list scrolls
endlessly, 20 rows a page.

The nearby place is one Nominatim reverse lookup at the course midpoint —
half-way along its length — made once by `Segments::GeocodePlaceJob` after the
course is committed (`Segments::PlaceGeocoder`): the geometry never changes. It
keeps a recognizable feature (a summit, a pass, a settlement) and falls back
from a road to the settlement around it. The midpoint leaves the instance only
when the operator configured `GEOCODING_BASE_URL`, the same consent as workout
toponymy. A virtual course is never geocoded. The place is local presentation:
it never enters a publication, the course `Note` or the API. The markers and
the sweeps are in `[devdoc:derivations]`.

The viewer's standing lives on the course page: the detail page previews the
board as the top 10 per sport under the Classements container — with a link to
the full board when a section overflows — and its *Mon rang* tile reads the
rank and the participant count (`3 / 12`, with the laurel podium stamp for a
top-three place), so the former `/leaderboards` directory no longer exists. The
personal efforts table marks the viewer's three best times per sport with the
personal-place trophy (gold record, silver, bronze; `DESIGN.md` §10.4). The
§19.6 opt-out toggle lives in that container's header and in the page `⋯` menu.
Every violation returns **404**, never 403, so no endpoint discloses the
existence of a record the viewer cannot read.

### 5.5 Anonymous rendering

A viewer reads a real name, linked to the profile, for their own effort, for
the accounts they follow, and for every effort on a course they created. Every
other row is rendered as below, and so is an effort with `anonymous = true` for
everyone:

- the name is `Allure::Leaderboard::Alias.for(...)`;
- the date is rendered as month and year only;
- no avatar, no profile link, no ShortUUID, no identity data attribute;
- the row is excluded from any ActivityPub serialization by §2.6.

A request spec asserts the negative directly: the rendered body of an anonymous
leaderboard contains no user ShortUUID, no profile path, no avatar URL and no
exact timestamp.

### 5.6 Local copy of a shared course

A signed-in viewer of a shared course may copy it into their own private
courses from the course's `⋯` menu, in the recorded direction or reversed; the
owner may create the reversed copy of their own segment or route (a loop is
already its own circuit). The copy is a new course, always **private**, and
preserves the source's `kind`: its geometry, distance, elevation aggregates and
stored elevation profile are frozen from the source — mirrored for the reversed
orientation, whose signature is recomputed on the reversed coordinates and
whose ascent and descent swap. `after_create_commit` matches the copy against
the copier's own workouts only, so a reversed copy only matches recordings made
the other way, and the source owner's course and board are untouched. A copy
never carries another account's source activity; the owner's own copy keeps the
link to the workout it reverses. There is no provenance column, no
anti-duplicate rule, and each copy is an independent segment.

### 5.7 Leaderboard categories

An account may declare a leaderboard category at `/settings/profile`:
`users.leaderboard_category`, `unspecified` (the default, never inferred),
`women` or `men`, guarded by the `users_leaderboard_category` check. It is a
sporting category for the boards, not an identity field: it is shown nowhere
else, never enters a publication snapshot, a remote representation, the REST
API, MCP, webhooks or `/admin`, and switching back to `unspecified` takes
effect on the next read.

The category is a **view** of a board, never a second eligibility rule.
`Segments::Categories` filters the ranking the viewer already reads — the §5.2
rows, best effort per athlete, `user` loaded — so it adds no query and no
stored state:

- `?category=women|men` on the full board combines with `?board=`; an unknown
  value reads as every athlete, like an unknown `board`;
- a category is offered on one sport's ranking only from `MIN_ATHLETES = 3`
  **distinct athletes** of that category among the rows the viewer sees. Below
  it, the section states so instead of listing anyone, and the switch is not
  rendered while no section reaches it;
- ranks are recomputed inside the filter;
- the course page's top-10 preview stays the general board; the « Mon rang »
  tile adds the viewer's place in their declared category (`2 / 5 · Femmes`)
  when that category is offered on their ranking;
- the index, the hub, the API `leaderboard` object and the standings stay
  general.

Residual disclosure, stated in the settings copy: whoever reads a board an
athlete appears on can tell their declared category through the filter — under
an alias on an aliased row, by name where §5.5 shows names — and, on a small
board, by subtraction from the other category. The threshold keeps a filter
from pointing at one or two people; it does not make the category secret. Age
groups are out of scope.

## 6. HTTP surface

```ruby
# Viewport read behind the discover map: readable shared courses intersecting
# `bbox`, simplified, capped, facts only.
get "/segments/discover_map", to: "segment_discoveries#show"

resources :segments do
  resource  :leaderboard, only: :show
  resource  :copy,        only: :create   # another account's course, forward or reversed
  resources :efforts,     only: :index
  resource  :track,       only: :show   # geometry, gated by segment visibility
  resource  :chart,       only: :show   # stored profile, same visibility gate
end

resources :workouts do
  resources :segments, only: %i[new create]   # selection from a source workout
  resource :segment_selection, only: :show    # owner-only indexed chart data
end
```

The workout detail view gains three sections, all gated by the existing
`:analysis` level: **efforts**, **laps** and **splits**.

Shared conventions with the workout core, preserved exactly:

- `Cache-Control: private, no-store` on every data endpoint;
- ShortUUID `ArgumentError` rescued to `ActiveRecord::RecordNotFound`;
- mutating actions scoped through `current_user`, never a global lookup
  followed by an ownership check;
- no raw Active Storage URL anywhere.

Navigation gains one entry in `config/navigation.rb`, section `explore`, key
`segments`, icon `flag`, `policy: :signed_in?`. Labels go in every locale file;
never a literal in the navigation file.

## 7. Frontend

Segment creation reuses the existing controllers rather than adding libraries:

- the elevation chart controller gains a brush selection that emits a
  point-index range;
- the map controller highlights the corresponding slice of the track;
- both keep their current `disconnect` teardown and in-flight fetch abort.

No new browser dependency. No inline styles. Tabler `.card`, `.row.row-deck`,
`.empty` and `.table` patterns only. The leaderboard uses the existing Pagy
integration. Coordinates stay `[longitude, latitude]` in every payload and are
never converted: MapLibre uses the same order.

The selection endpoint is owner-only and returns the existing chart fields plus
the original flattened `index` and recording `segment_index`. The public chart
contract is unchanged; the browser submits only those indexes and the server
reconstructs the selected geometry from the source workout.

The segment detail page renders the stored course profile: the same elevation
chart controller as a workout's single elevation area, fed by
`GET /segments/:id/chart` from `segments.elevation_profile`, with the distance
table as its text equivalent (`DESIGN.md` §15.1). There is no secondary series,
no toponymic route story and no brush selection; the profile follows the
course's own visibility, like the track. A course with `NULL` or `[]` shows the
unavailable state instead of a request. The snapshot is frozen at creation:
deleting or re-analysing the source never changes it, and a received course has
none. The track endpoint carries the cumulative vertex distances
(`Allure::Segments::TrackSeries`), so hovering either the map or the profile
marks the other by distance, exactly as on a workout.

The personal efforts card carries the viewer's progression on the course once
they hold two efforts: `Allure::Segments::EffortHistory` orders their own
efforts by start, splits them per sport, gives the three best times their
personal place (time, then the earlier start, then the earlier row — §4.6, like
the efforts table), and computes the trend: each outing (workout) counts once,
as the mean of its laps, from three outings, through the pure
`Allure::Stats::RobustTrend` on a time axis. Under eight outings it is the
Theil–Sen line (the median of the pairwise slopes), which a bad day does not
tilt; from eight it is Cleveland's robust LOWESS: a locally linear fit, so the
ends are not flattened and irregular spacing is respected, tricube-weighted
over the nearest two thirds of the outings capped at 30, and reweighted by two
bisquare passes over the residuals; outings closer than 1 % of the range share
an interpolated fit. The trend is evaluated on 99 evenly spaced inner positions
plus every outing, and drawn with straight segments: a spline through one value
per outing overshot beside a long gap and ran backwards. Each stretch is
flagged `reliable`; it is not under five outings, nor inside a gap longer than
six months and than 15 % of the history, and the payload carries it as two
aligned series (`trend`, `trend_uncertain`, the dotted one) sharing their
junctions. The payload is embedded in the page (no endpoint, no cache), carries
only the viewer's own efforts, and is never published or federated. One chart
is drawn per sport holding two efforts (`EffortHistory#chartable_series`), each
with its own payload; the `segment-progress-chart` controller draws the points,
the trophy callouts and the grey trend with ECharts, and each chart's
chronological table is its text equivalent.

## 8. Jobs

| Job | Trigger | Idempotency |
|---|---|---|
| `Segments::MatchWorkoutJob` | after import commit, and on manual re-match | deletes efforts for that workout whose `matcher_version` is stale, then reinserts in one transaction; the workout row is locked for that transaction, so concurrent runs (import plus an elevation reanalysis or a segment backfill) serialize instead of racing the unique effort key |
| `Segments::BackfillSegmentJob` | segment creation | bounded batches over a cursor; resumable |

Eligibility has no job: `Segments::Listing` derives it at read time, so there is
nothing to refresh when a publication, exclusion, visibility or zone changes.

Both follow `Workouts::RenderRouteImageJob`: `queue_as :default`, `retry_on`
with polynomial backoff for transient failures, and `discard_on
ActiveRecord::DeserializationError` and `ActiveRecord::RecordNotFound`. Enqueue
happens after commit. A failed enqueue is reported through
`Rails.error.report(handled: true)` and never rolls back the user's import.

## 9. Tests

### 9.1 Fixtures

| Fixture | Purpose |
|---|---|
| `three_laps.gpx` | 400 m circuit repeated three times; lap detection and occurrence ordering |
| `out_and_back.gpx` | the return leg must **not** match a one-way segment |
| `parallel_roads.gpx` | carriageway and service road 15 m apart; false-positive regression |
| `gap_inside_segment.gpx` | recording pause inside a segment; no effort is created |
| `partial_overlap.gpx` | enters and leaves the corridor without completing |
| `route_repeat.gpx` | same complete track on a later date; route history backfill |

Expected values are hand-calculated or independently verified. They are never
generated by running the implementation under test and recording its output.

### 9.2 Pure unit specs

- Resampler: idempotence, exact endpoint preservation, degenerate two-point
  input, antimeridian crossing.
- Fréchet: identical curves score zero; a uniformly offset curve scores the
  offset; a **reversed** curve is rejected; a partial curve is rejected; the
  band never excludes a valid optimum.
- Projection: interpolated time on synthetic constant-speed input; boundary
  cases at the first and last vertex.
- `ShapeSignature`: stability across resampling densities, fixed 64-value
  cardinality, and **an explicit spec documenting rotation invariance as a
  known limitation**, asserting that two rotated copies collide.
- `LoopDetector`: three-lap circuit, an out-and-back that must not loop, and a
  loop shorter than `min_loop_distance`.
- `PointStream`: cross-segment distance and time accumulation matching
  `ChartSeries`.
- `Splits`: exact kilometre crossings, trailing partial split flagged, imperial
  unit switch.
- `Alias`: fixed vectors, stability for a given pair, difference across
  segments, deterministic collision resolution.

### 9.3 Model and database specs

- Every check constraint, including `cardinality(signature) = 64`.
- Unique `(segment_id, workout_id, occurrence_index)`.
- Cascade deletion from workout and from segment; `ON DELETE SET NULL` on
  `source_workout_id`.
- A segment cannot be saved non-private when it is a loop.

### 9.4 Request specs

- Full visibility matrix: `private`, `followers_only`, `public` crossed with
  owner, follower and signed-in stranger; an anonymous visitor is redirected to
  sign-in on every surface.
- Private segment returns 404 to a stranger, not 403.
- A signed-in stranger's leaderboard body contains no user ShortUUID, profile
  path, avatar URL or exact timestamp.
- Cache headers on every data endpoint.
- Segment creation is scoped to the current user's own workouts.

### 9.5 Job specs

- `MatchWorkoutJob` run twice produces identical rows.
- A `matcher_version` bump invalidates and rebuilds efforts.
- `BackfillSegmentJob` resumes correctly mid-cursor.
- `Segments::Listing` includes and excludes efforts for every eligibility
  condition, without any stored snapshot.

### 9.6 Browser verification

Through the Compose Playwright browser at `http://rails:3001`: segment creation
from map and chart, leaderboard, laps, splits, personal best, light and dark
themes, desktop and mobile widths, and Turbo back/forward with clean teardown.
Vite HMR websocket noise from the isolated browser is not an application error.

## 10. Out of scope

- Automatic creation of segments or routes without an explicit user action.
- Freehand segment drawing that is not derived from a stored workout.
- Importing Wanderer trails as routes.
- Federating efforts, routes and leaderboards. Course-only distribution is
  `SEGMENTS-FEDERATION.md`; no effort, athlete, alias or leaderboard row ever
  leaves the instance.
- Neural embeddings and `pgvector`.
- Heatmaps, popularity surfaces and course-record notifications.
- Segment moderation, reporting or hazard flags.
- Cross-instance leaderboards.
- Age groups beside the §5.7 categories.
- A per-sport default for `match_tolerance_meters`.
- A consensus centreline refined from matched efforts.
- Whether efforts on a followers-only segment survive an unfollow, or are
  delisted.
- Whether an effort should be recomputable from a sanitized track rather than
  the raw track.
