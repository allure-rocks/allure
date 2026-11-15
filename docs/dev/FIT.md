# FIT import contract

FIT file import: an in-house binary decoder under `lib/allure/fit/`, its wiring
into the single-file and batch import paths, and the test strategy that keeps a
hand-written binary decoder honest. `WORKOUT.md` covers the shared workout
core; this document covers the FIT-specific boundary.

## 1. What FIT import does

An authenticated user can:

1. Upload a single `.fit` file through the same form that accepts `.gpx`.
2. Upload `.fit`, `.fit.gz`, and ZIP archives mixing `.gpx` and `.fit` through
   the existing batch import, including `.gpx.gz` and `.fit.gz` ZIP entries.
3. Have the sport selected automatically from the FIT `sport`/`sub_sport`
   enumeration, falling back to the selected sport when the activity is not in
   the Allure catalog.
4. See the imported workout's map, elevation profile, splits, route image,
   segment efforts and publication behave exactly as a GPX import does.
5. Download the original `.fit` file, byte-identical, from the owner-only
   endpoint.

Deliberate non-goals: multisport/transition files; course, workout, monitoring
and settings FIT file types; and a semantic (non-byte) duplicate fingerprint.
Recorded laps are stored, but they are not yet the source of the splits.

## 2. Locked decisions

| Decision | Choice | Rationale |
|---|---|---|
| Decoder | In-house, `lib/allure/fit/`, zero runtime dependencies | See §2.1 |
| Value contract | Existing `Allure::Gpx::{Track, Segment, Point, ActivitySignal}`, unrenamed | See §2.2 |
| Format detection | Sniffed magic bytes, not file extension | Extension is attacker-controlled and unreliable in archives |
| Segment splitting | `event == timer && event_type == stop_all` | FIT has no `<trkseg>` equivalent |
| Sport detection | One `ActivitySignal` per file at confidence 100 | Reuses `ActivityDetector`; see §5 |
| Committed fixtures | Synthetic bytes from a Ruby FIT encoder only | See §9; no third-party personal GPS data enters the repository |
| Scope | Single-file **and** batch/archive | Real exports are ZIPs of `.fit.gz`; single-file alone misses the use case |

### 2.1 Why an in-house decoder

The decoder is in-house, under `lib/allure/fit/`, with no runtime dependency.
No existing gem met the maintenance, Ruby 4 and licensing requirements for this
repository, and the format boundary is small enough to own: the parser returns
the same `Allure::Gpx::Track` value as GPX, so nothing below it knows the source
format.

This aligns with the existing architecture: calculation-heavy,
framework-independent behaviour lives under `lib/allure/`, and
`Allure::Gpx::Parser` set the precedent of owning the format boundary rather
than exposing a gem's object types to the domain.

### 2.2 Why the value objects keep their `Gpx` name

`Allure::Gpx::{Track, Segment, Point, ActivitySignal}` are the shared,
cross-format track contract. `Allure::Fit::Parser` returns an
`Allure::Gpx::Track`.

This is assumed naming debt, recorded so it is not rediscovered as a bug. Two
alternatives were considered and rejected:

- **`Allure::Activity::*`** — collides with the implemented `Segment` model and
  `Allure::Segments::{Matcher, Point, PointStream, EffortMetrics}`, and stutters
  as `Allure::Activity::ActivitySignal`. "Activity" is also already taken by
  `ActivityDetector` and `ActivityTypeCatalog`.
- **`Allure::Recording::*`** — semantically the best fit, matching the
  "recording segment" vocabulary. Rejected on cost: the rename touches roughly
  40 files, `Allure::Gpx::Geo` alone has 37 references, and it would reach into
  `Allure::Geometry::*`, `Allure::Segments::*`, `Privacy::ZoneFilter` and
  `Workouts::Publisher`.

Inside the `Gpx` namespace, "segment" unambiguously means `<trkseg>`, and the
disambiguation against the leaderboard `Segment` still holds. The rename
remains possible later as an isolated commit.

### 2.3 What does not change

The pipeline below the parser is format-agnostic:

`Allure::Gpx::Analyzer` · `PointSerializer` · `ChartSeries` · `TrackSeries` ·
`Splits` · `Workouts::RouteImageRenderer` · `Segments::Matcher` ·
`Segments::Creator` · the map and chart Stimulus controllers · the track and
chart endpoints · `Workouts::Publisher`.

In particular, `Allure::Federation::Privacy::SanitizedGpxBuilder` re-emits GPX
1.1 from persisted `track_segments.points` regardless of source format, so a
FIT import publishes a sanitized GPX with no code change. The `gpx`
representation key in `SanitizedPublicationBuilder::REPRESENTATION_KEYS` is a
federation contract and is **not** renamed.

`workouts.import_format` is purely internal: it appears in no publication
payload, no federated document and no URL.

## 3. FIT binary format contract

The decoder implements the Garmin FIT Protocol as documented at
<https://developer.garmin.com/fit/protocol/>. This section fixes the subset the
implementation must handle, because incomplete handling of any item below
corrupts records **silently** rather than raising.

### 3.1 File header

12 or 14 bytes:

| Offset | Size | Field |
|---:|---:|---|
| 0 | 1 | `header_size` (12 or 14) |
| 1 | 1 | `protocol_version` |
| 2 | 2 | `profile_version` (little-endian) |
| 4 | 4 | `data_size` (little-endian, excludes header and trailing CRC) |
| 8 | 4 | `.FIT` signature, bytes `0x2E 0x46 0x49 0x54` |
| 12 | 2 | header CRC, present only when `header_size == 14` |

A 14-byte header whose CRC is `0x0000` is treated as "not computed" and
accepted, as the specification allows.

**Chained files.** After `data_size` bytes plus the 2-byte file CRC, remaining
bytes may begin another complete FIT file. The decoder must continue into it
and merge its messages. Some devices chain an activity file after a settings
file; stopping at the first file loses the track entirely. Real activity files
chain dozens of small companion files — the conformance corpus reaches 36 — so
the chain cap is 64; `MAX_BYTES` remains the actual bound on the work.

### 3.2 Record headers

One byte precedes every record.

- **Normal header** (bit 7 = 0): bit 6 selects definition (1) or data (0);
  bit 5 is the developer-data flag on definition messages; bit 4 is reserved;
  bits 3–0 are the local message type.
- **Compressed timestamp header** (bit 7 = 1): bits 6–5 are the local message
  type; bits 4–0 are a 5-bit time offset applied to a rolling `last_timestamp`.

The compressed form is mandatory to implement. It is common on
space-constrained devices, and misreading its header byte as a normal header
desynchronises the entire remainder of the stream.

### 3.3 Definition messages

| Size | Field |
|---:|---|
| 1 | reserved |
| 1 | architecture: 0 = little-endian, 1 = big-endian |
| 2 | global message number, in the declared architecture |
| 1 | number of fields |
| 3 × n | per field: field definition number, size in bytes, base type |

When the developer-data flag is set, a further byte gives the developer field
count, followed by 3 bytes each (field number, size, developer data index).

Big-endian definitions occur in the wild. Developer fields need not be
interpreted, but their declared sizes **must** be consumed, or every subsequent
field in that message is read at the wrong offset.

Definitions are scoped per local message type and are replaced, not merged,
when redefined mid-file.

### 3.4 Base types

| Value | Type | Bytes | Invalid |
|---|---|---|---:|
| `0x00` | enum | 1 | `0xFF` |
| `0x01` | sint8 | 1 | `0x7F` |
| `0x02` | uint8 | 1 | `0xFF` |
| `0x83` | sint16 | 2 | `0x7FFF` |
| `0x84` | uint16 | 2 | `0xFFFF` |
| `0x85` | sint32 | 4 | `0x7FFFFFFF` |
| `0x86` | uint32 | 4 | `0xFFFFFFFF` |
| `0x07` | string | 1 | `0x00` |
| `0x88` | float32 | 4 | all bits set |
| `0x89` | float64 | 8 | all bits set |
| `0x0A` | uint8z | 1 | `0x00` |
| `0x8B` | uint16z | 2 | `0x0000` |
| `0x8C` | uint32z | 4 | `0x00000000` |
| `0x0D` | byte | 1 | `0xFF` |
| `0x8E` | sint64 | 8 | `0x7FFF…` |
| `0x8F` | uint64 | 8 | all bits set |
| `0x90` | uint64z | 8 | `0x0000…` |

A field equal to its invalid value decodes to `nil`, never to the raw sentinel.
The sentinel is a *value*, not a byte pattern, so it must be compared using the
message's own architecture; a little-endian comparison misses every sentinel in
a big-endian message.

A field whose declared size exceeds its base type size is an array; the decoder
reads the first element for scalar fields and ignores the remainder, which is
sufficient for every field in §3.5. Strings are null-terminated and UTF-8, and
are sanitized with `encode("UTF-8", invalid: :replace, undef: :replace)`.

A base type number outside this table decodes to `nil` and its declared size is
still consumed. This is deliberate leniency: field sizes come from the
definition message rather than from the base type, so an unrecognised type
cannot desynchronise the stream, and rejecting a whole activity over one
unreadable field in a message Allure ignores would be a poor trade.

### 3.5 Message profile subset

`lib/allure/fit/profile.rb` carries a hand-curated table, not a generated SDK
profile. Only these messages and fields are interpreted; every other message is
skipped by its declared length. The session numbering of the power and
elevation totals is one above the lap numbering: session 21 is `max_power`
where lap 21 is `total_ascent`. `max_power` is named only so the offset stays
visible; it is not consumed.

| No. | Message | Fields |
|---:|---|---|
| 0 | `file_id` | 0 `type`, 1 `manufacturer`, 2 `product`, 3 `serial_number`, 4 `time_created`, 8 `product_name` |
| 18 | `session` | 5 `sport`, 6 `sub_sport`, 11 `total_calories`, 15 `max_speed`, 21 `max_power`, 22 `total_ascent`, 23 `total_descent`, 125 `enhanced_max_speed` |
| 19 | `lap` | 253 `timestamp`, 254 `message_index`, 7 `total_elapsed_time`, 8 `total_timer_time`, 9 `total_distance`, 13 `avg_speed`, 14 `max_speed`, 15 `avg_heart_rate`, 16 `max_heart_rate`, 17 `avg_cadence`, 19 `avg_power`, 21 `total_ascent`, 22 `total_descent`, 24 `lap_trigger`, 52 `total_moving_time`, 110 `enhanced_avg_speed`, 111 `enhanced_max_speed` |
| 20 | `record` | 253 `timestamp`, 0 `position_lat`, 1 `position_long`, 2 `altitude`, 3 `heart_rate`, 4 `cadence`, 7 `power`, 78 `enhanced_altitude` |
| 21 | `event` | 253 `timestamp`, 0 `event`, 1 `event_type` |
| 23 | `device_info` | 2 `manufacturer`, 27 `product_name` |

Plus the `file`, `sport`, `sub_sport`, `event` and `event_type` enumerations.
Device names live apart, in `Allure::Fit::Devices`: the whole `manufacturer`
enumeration and the `garmin_product` one (read for manufacturers 1, 13, 15 and
89), generated from the FIT SDK profile 21.218.0 with hand-written display
spellings and regional variants folded into their model, `development` (255)
left out. Other brands number their products privately and publish no list, so
their table holds only codes confirmed by a real file writing the model name
beside its code, or by the SDK itself (Favero).

A provider that writes no `product_name` can still be named from its raw
`file_id` fingerprint (`manufacturer`/`product`/`serial_number`), declared in
`Allure::Virtual::Platforms` and consulted before the generic fallbacks
(`[devdoc:virtual-platforms]`). EXR's fingerprint is
`manufacturer: 255, product: 22, serial_number: 1234`; it names the device but
never changes the detected sport, exactly like a `product_name`.

### 3.6 CRC

The trailing 2-byte CRC uses the FIT 16-entry nibble lookup table. It is
verified. A mismatch raises `Allure::Fit::MalformedFitError` rather than
returning a partially decoded track.

## 4. Conversion rules

`Allure::Fit::Parser#parse(io)` returns one `Allure::Gpx::Track`, matching the
GPX parser's contract exactly.

| Quantity | Rule |
|---|---|
| Latitude / longitude | Semicircles: `value * 180.0 / 2**31`; a `position_lat`/`position_long` declared uint32 (`0x86`) instead of the profile's sint32 (`0x85`) is reinterpreted as two's-complement signed, because some devices emit negative semicircles that way |
| Timestamp | FIT epoch `1989-12-31T00:00:00Z`, i.e. Unix offset `631_065_600` |
| Elevation | `enhanced_altitude` when present, else `altitude`; both scale 5, offset 500, giving `raw / 5.0 - 500.0`; exact zeros are placeholders in a partially recorded segment and become missing (`WORKOUT.md` §6.6) |
| Heart rate / cadence | uint8, bpm and rpm/spm; non-positive heart rate (`0` bpm strap dropout) is treated as missing, while `0` cadence (coasting) stays valid |
| Power | uint16 watts |
| Calories | `session.total_calories`, kcal, matching the existing `workouts.calories` column |
| Maximum speed | Prefer `session.enhanced_max_speed`, then `session.max_speed`, then the greatest lap maximum; speed scale 1000, persisted as m/s |
| Device elevation totals | The recorded laps are summed by `Workouts::DeviceElevationTotals` when they cover at least 95 % of the activity; otherwise `session.total_ascent`/`total_descent` are exposed as `Track#source_ascent`/`source_descent` (`[devdoc:elevation]`) |
| Creator | A registered virtual-platform fingerprint on `file_id` (`[devdoc:virtual-platforms]`); else `file_id.product_name`; else the `manufacturer`/`product` model; else `manufacturer`; else `device_info.product_name`; else `device_info.manufacturer` |

Units already match the SI storage contract of `WORKOUT.md` §2.1, so no
conversion is introduced at the persistence boundary.

### 4.1 File type

Only `file_id.type == activity` (4) is accepted. Course, workout, settings,
monitoring, totals and segment files raise
`Allure::Fit::UnsupportedFitError`. Attempting to import a course file as a
workout would fabricate a workout that never happened.

A file carrying **no** `file_id` message raises the same error. The
specification makes `file_id` mandatory and every real encoder emits it, so its
absence cannot be used to bypass the file-type check.

### 4.2 Record selection

Records missing a timestamp are skipped silently. Records missing a position
are kept: their sensor readings belong to the activity, and a file that never
reached a fix is imported as a **positionless recording**
(`[devdoc:no-gps]`). Within a file that did reach a fix, the position-less
records stay skipped exactly as before — devices emit them before GPS lock and
during indoor portions of an activity, and the positioned segments ignore them.

`Allure::Gpx::NoTrackError` therefore means "fewer than two timed records": a
file with no usable data at all, which the importer maps to a localized
validation error.

The 250,000-point cap of `Allure::Gpx::Parser::DEFAULT_MAX_POINTS` is shared and
enforced while reading, raising `Allure::Gpx::TooManyPointsError`. It bounds the
analyzer's linear work: a long ultra can legitimately exceed 100,000 points in
an upload the 25 MB byte limit already accepts.

### 4.3 Segment splitting

FIT has no `<trkseg>`. Recording segments are derived from timer events:

1. Collect `event` and `record` messages and sort them by timestamp. Some
   devices write all events after all records; document order is not reliable.
2. On `event == timer` (0) and `event_type == stop_all` (4), close the current
   segment and begin a new one.
3. Drop segments with fewer than two points, preserving the parser invariant.

### 4.4 Timestamps

FIT timestamps have one-second resolution, so consecutive records can share a
timestamp. The existing contract requires timestamps to be *non-decreasing*
within a segment, so equal timestamps are valid and produce zero-duration
intervals, which `Allure::Gpx::Analyzer` already excludes from moving-time and
maximum-speed calculations.

Real devices occasionally emit an isolated record whose clock glitched
backwards: the conformance corpus holds two activities with single −1 s pairs.
Those records are dropped and the activity imports;
`Allure::Fit::Parser::MAX_BACKWARD_RECORDS` bounds the consecutive tolerance. A
backward jump larger than `CLOCK_RESET_THRESHOLD` (one hour), or a longer
unbroken run, is a clock correction: the corpus also holds one activity whose
first 105 records carry a clock two years ahead before the device settles on
the true time. The records of the abandoned epoch are discarded — including its
stop marks — and parsing continues from the corrected clock. A fully reversed
file therefore loses its earlier epoch and ends as `Allure::Gpx::NoTrackError`;
the FIT parser no longer raises `NonMonotonicTimestampError`. The GPX parser
stays strict: document-order reversal there means a corrupt file, not a device
glitch.

### 4.5 Recorded laps

Global message 19 values describe each lap independently; they are not running
activity totals. The supported Garmin Profile fields are:

| Field | Number | Scale |
|---|---:|---:|
| `message_index` | 254 | 1 |
| `timestamp` | 253 | FIT epoch |
| `total_elapsed_time` / `total_timer_time` | 7 / 8 | 1000 |
| `total_distance` | 9 | 100 |
| `avg_speed` / `max_speed` | 13 / 14 | 1000 |
| `avg_heart_rate` / `max_heart_rate` | 15 / 16 | 1 |
| `avg_cadence` / `avg_power` | 17 / 19 | 1 |
| `total_ascent` / `total_descent` | 21 / 22 | 1 |
| `lap_trigger` | 24 | enum |
| `total_moving_time` | 52 | 1000 |
| `enhanced_avg_speed` / `enhanced_max_speed` | 110 / 111 | 1000 |

Enhanced speed wins when both forms are present. Elapsed and moving values are
rounded to the integer-second persistence contract; moving time falls back to
timer time and is capped at elapsed time. Average speed remains distance divided
by moving time when both are usable, matching workout metric semantics.

`message_index` numbers the lap when it is usable, preserving the device's own
numbering and its gaps (the flag bits are masked). A device that reuses one
index for every lap of an interval session would break the per-workout
uniqueness of `laps.number`, so a colliding index falls back to the next free
number and the laps still persist in order.

## 5. Sport detection

FIT carries a real `sport`/`sub_sport` enumeration, which is far more reliable
than the free-form text signals GPX offers. Rather than duplicating detection
logic, `Allure::Fit::SportCatalog` translates the pair into an alias string that
**already exists** in `Allure::ActivityTypeCatalog::SPORT_ALIASES`, and emits it
as a single `ActivitySignal`.

```ruby
Allure::Gpx::ActivitySignal.new(source: :fit_sport, value: "mountain biking")
```

`Allure::ActivityDetector::SOURCE_CONFIDENCE` gains `fit_sport: 100`.

**Exactly one signal is emitted per file.** Emitting both `sport` and
`sub_sport` at equal confidence would resolve to two different sports and
trigger the ambiguity guard, silently falling back to the user-selected sport —
the opposite of the intent.

Representative mappings:

| FIT sport | FIT sub_sport | Alias emitted | Resolved slug |
|---|---|---|---|
| `running` | `trail` | `trail running` | `trail` |
| `running` | `street`, `track`, generic | `running` | `running` |
| `running` | `treadmill`, `indoor_running`, `virtual_activity` | `virtual run` | `running_virtual` |
| `cycling` | `mountain`, `downhill` | `mountain biking` | `mountain_biking` |
| `cycling` | `road` | `road cycling` | `cycling_road` |
| `cycling` | `gravel_cycling`, `mixed_surface` | `gravel` | `cycling_gravel` |
| `cycling` | `e_bike_mountain` | `emtb` | `mountain_biking_electric` |
| `cycling` | `e_bike_fitness` | `ebike` | `cycling_electric` |
| `cycling` | `commuting` | `cycling` (+ `commute_hint`) | `cycling` |
| `cycling` | `indoor_cycling`, `spin`, `virtual_activity` | `virtual cycling` | `cycling_virtual` |
| `e_biking` | any | `ebike` | `cycling_electric` |
| `e_biking` | `commuting` | `ebike` (+ `commute_hint`) | `cycling_electric` |
| `swimming` | `open_water` | `open water swimming` | `open_water_swimming` |
| `swimming` | `lap_swimming`, generic | `pool swimming` | `pool_swimming` |
| `rowing` | `indoor_rowing` | `virtual rowing` | `rowing_virtual` |
| `alpine_skiing` | `backcountry` | `ski touring` | `skiing_touring` |
| `snowboarding` | any | `snowboarding` | `snowboarding` |
| `hiking` | `trail`, generic | `hiking` | `hiking` |
| `walking` | any | `walking` | `walking` |
| `cross_country_skiing` | any | `cross country skiing` | `skiing_cross_country` |
| `alpine_skiing` | any | `alpine skiing` | `skiing_alpine` |
| `rowing` | any | `rowing` | `rowing` |
| `mountaineering` | any | `mountaineering` | `mountaineering` |
| `snowshoeing` | any | `snowshoeing` | `snowshoes` |
| `inline_skating` | any | `inline skating` | `inline_skating` |
| `ice_skating` | any | `ice skating` | `ice_skating` |
| `stand_up_paddleboarding` | any | `standup paddleboarding` | `standup_paddleboarding` |
| `kayaking` | any | `kayaking` | `kayaking` |
| `windsurfing` | any | `windsurfing` | `windsurfing` |
| `tennis` | any | `tennis` | `tennis_outdoor` |

A commuting sub-sport is the one FIT pair that carries two facts: the sport
resolves to `cycling`/`cycling_electric` through the normal alias, and the
parser records `commute_hint` on the track so the importer persists the commute
flag. No other parser can produce that hint.

Sports outside the Allure catalog — `sailing`, `diving`, `snorkeling`,
`volleyball`, `paddling` (ambiguous between kayak, canoe and SUP), `flying`,
`training`, `fitness_equipment` — emit **no signal at all** and use the import
fallback.

## 6. Error taxonomy

Reused unchanged, so the importer's existing localized mappings apply:

`Allure::Gpx::NoTrackError` · `TooManyPointsError` · `MissingTimestampError` ·
`NonMonotonicTimestampError` · `InvalidPointError`

New:

| Class | Raised when | i18n key |
|---|---|---|
| `Allure::Fit::MalformedFitError` | bad header size, missing `.FIT` signature, header or file CRC mismatch, truncated stream, undefined local message type, compressed timestamp before any full timestamp, oversized or empty input | `workouts.import.errors.malformed_fit` |
| `Allure::Fit::UnsupportedFitError` | `file_id.type` is not `activity`, or no `file_id` message is present | `workouts.import.errors.unsupported_fit_type` |

Both inherit from `Allure::Fit::Error < StandardError`.

Every decoding failure must surface as one of these. A `.fit` upload must never
produce a 500, an `ArgumentError` from `unpack1`, an unbounded read, or a
`NoMethodError` on `nil`. This is a hard requirement, verified by the
conformance corpus in §9.

## 7. Data model

`Workout::IMPORT_FORMATS` is `%w[gpx fit tcx kml]`, mirrored by the database
check constraint. `import_format` is internal and appears in no publication
payload, federated document or URL.

FIT-specific data that has no home in the workout columns is stored where the
shared model already puts it:

- recorded laps become `laps` rows, with their own numbering and metrics;
- the device's air temperature becomes the `temp` point key;
- a positionless recording keeps its device distance and speed in the point
  stream (`[devdoc:no-gps]`);
- device serial numbers and session summaries are not persisted.

## 8. Import paths

### 8.1 `Workouts::Importer`

Format knowledge lives in `Allure::ImportFormat`, not in the importer.
`ArchiveReader` needs the same extensions, storage content types and magic
bytes, and duplicating the `.FIT` signature in two files is exactly the drift
this repository avoids elsewhere.

```ruby
Format = Data.define(:key, :extension, :content_type, :parser_class)
ImportFormat.detect(io)          # magic bytes -> Format or nil, rewinds
ImportFormat.for_extension(ext)  # advisory, for error messages
ImportFormat.for_key(key)        # resolves a persisted import_format
```

- `ALLOWED_EXTENSIONS` becomes `ImportFormat::EXTENSIONS`.
- **The uploaded content type is not checked at all.** Browsers report a `.fit`
  as `application/octet-stream`, `application/vnd.ant.fit`,
  `application/fits`, or nothing, depending on platform. An allowlist would
  only produce false rejections: the client-supplied MIME header is not
  evidence, and the magic-byte sniff is strictly stronger.
- The sniff becomes `ImportFormat.detect`. **Content beats extension**: a file
  named `.gpx` whose bytes are FIT is imported as FIT and stored with the FIT
  extension and content type. The extension is still validated so the error
  message is clear, but it carries no authority.
- `parse_track` dispatches through `@format.parser` and translates both error
  hierarchies.
- `create_blob` and `safe_filename` derive the content type and extension from
  the detected format.
- `persist_workout` writes the detected `import_format`.

Everything else — SHA-256 digest, duplicate handling, blob compensation on
rollback, post-commit job enqueueing — is untouched.

### 8.2 `Workouts::ArchiveReader`

- Extension dispatch accepts `.fit` alongside `.gpx` for direct sources.
- Gzip: the `"workout.gpx"` coercion generalizes so `activity.fit.gz` yields
  `activity.fit`; the decompressed content is sniffed so content wins over a
  misleading inner extension.
- ZIP accepts `.gpx` and `.fit`, plus `.gpx.gz` and `.fit.gz` entries. The
  latter are decompressed in-process and passed through the same content
  detector, which supports the gzip members used by Strava exports.
- `no_track_entries` replaces the GPX-specific empty-archive error with a
  generalized message.

The existing hardening remains in place: unsafe path rejection, nested ZIP/TAR
skipping, per-entry 25 MB cap on decompressed track bytes, 1000:1 ZIP
compression ratio ceiling, 2 GB cumulative budget, and in-process reading with
no shelled extraction. `MAX_ARCHIVE_ENTRIES` is unchanged and still includes
every non-directory ZIP entry.

### 8.3 `Workouts::ImportBatchJob`

Per-entry progress, `source_key` idempotency, duplicate pre-check and
cancellation are untouched. The forced `content_type:` keyword is gone with the
importer's content-type check.

### 8.4 HTTP and views

- `WorkoutFilesController` resolves the fallback content type through
  `ImportFormat.for_key(workout.import_format)`; the filename follows the blob.
- The workout form and the import page accept `.fit` and
  `application/vnd.ant.fit`.
- The form parameter is `track_file`, not `gpx_file`, across the controller,
  the error attachment, the form field and the locale keys. The label is
  user-visible; leaving it naming one of several accepted formats is a durable
  trap.

### 8.5 Internationalization

`fr.yml` and `en.yml` in the same patch, since missing translations raise in
development and test.

Renamed: `activerecord.attributes.workout.gpx_file` → `track_file`,
`workouts.form.gpx_file{,_hint}` → `track_file{,_hint}`,
`workouts.show.download_gpx` → `download_file`.

Reworded, because they become **wrong** rather than merely imprecise: a FIT
file carries no track name or description, so the parser returns nil for both
and a FIT workout is always titled from sport and date. `title_hint` and
`description_hint` therefore say "if the file has one".
`import.errors.unsupported_format` and `missing_extension` are format-neutral.
`batch_import.form.source_files{,_hint}` is format-neutral too.

New: `import.errors.malformed_fit`, `import.errors.unsupported_fit_type`,
`batch_import.errors.no_track_entries`.

## 9. Test plan

A hand-written binary decoder has a specific failure mode: it is tested against
the author's own assumptions about the format. The test plan is built in two
tiers to address exactly that.

### 9.1 Tier 1 — committed, synthetic, deterministic

`spec/support/fit_builder.rb` is a small deterministic **FIT encoder** in Ruby
that produces byte strings for each scenario. Nothing binary is committed: the
fixtures are readable Ruby, reviewable in a diff, and contain no personal data.
This runs in `dip rspec` and on GitHub Actions, fully offline under the WebMock
ban.

Scenarios:

| Scenario | Asserts |
|---|---|
| nominal activity | full `Track`, coordinates, timestamps, elevation |
| multi-segment | `stop_all` closes a segment; ordering preserved |
| events after records | timestamp sort, not document order |
| compressed timestamp headers | rolling offset applied correctly |
| big-endian definition | architecture byte honoured |
| developer data fields | declared sizes consumed, subsequent fields aligned |
| chained files | second file's messages merged |
| redefined local message type | definition replaced, not merged |
| invalid-value sentinels | decode to `nil`, never to `0xFF…` |
| records before GPS lock | skipped without error on a positioned file |
| no GPS at all | imported as a positionless recording (`[devdoc:no-gps]`) |
| fewer than two timed records | `NoTrackError` |
| non-activity `file_id.type` | `UnsupportedFitError` |
| truncated stream, bad signature, CRC mismatch | `MalformedFitError` |
| point cap exceeded | `TooManyPointsError` |
| decreasing timestamps | isolated backward records dropped; a clock correction restarts from the corrected epoch; a reversed file loses its earlier epoch and raises `NoTrackError` |
| repeated timestamps | accepted, zero-duration intervals |
| HR / cadence / power present and absent | correct `Point` attributes |
| `sport`/`sub_sport` combinations | one signal, expected slug |

Expected metric values are hand-calculated, never produced by running the
implementation under test.

### 9.2 Tier 2 — conformance corpus, untracked, optional

<https://github.com/ThomasKuehne/FIT-test-files> is a large corpus of real
activity files spanning Garmin, COROS, Suunto, Wahoo, Zwift, Bryton, Karoo,
Nike, Wattbike, TrainingPeaks and Apple Watch, from 1998 to 2026, plus
`AllFitMessageTypes.fit`, a synthetic file containing at least one instance of
every message the Garmin C# SDK supports. At the pinned revision
`3d895613ef90fdcf958d9518da942385271128e5`, the `Activity/` tree contains 4,066
files; the README's activity table is only a curated sample.

**It must not be committed.** That repository has no `LICENSE` file and no
copyright statement, and its `sources.txt` is 68,000 lines of URLs to
third-party public uploads. The files are real recorded activities by
identifiable people. It is treated like `references_apps/` — local, untracked,
read-only reference material:

- cloned to `references_apps/fit-test-files/`, which is covered by the
  repository-wide ignored `references_apps/` path;
- fetched by the documented `script/fetch-fit-corpus`, using a sparse checkout
  of only `Activity/`, `AllFitMessageTypes.fit`, and `README.md`;
- `spec/lib/allure/fit/corpus_spec.rb` **skips cleanly** when the directory is
  absent, so CI and fresh checkouts are unaffected.

When present it asserts:

1. **No unhandled failure.** Every file either parses or raises
   `Allure::Fit::MalformedFitError`, `UnsupportedFitError`, or one of the shared
   `Allure::Gpx` errors. No other exception class is acceptable.
2. **GPS files analyse.** Files with GPS produce a `Track` that
   `Allure::Gpx::Analyzer` processes without raising, yielding non-negative
   distance and a `started_at`.
3. **Indoor files import.** Representative treadmill, yoga, strength and
   breathing files are analysed as positionless recordings: non-negative
   distance, duration and their sensor channels, no bounds and no elevation
   (`[devdoc:no-gps]`). A diving file whose records carry no timestamp at all
   still raises `NoTrackError`. Some indoor and diving activities contain GPS
   and are analysed normally.
4. **Sport mapping is externally verified for curated samples.** Many corpus
   filenames encode sport and sub_sport identifiers
   (`Activity_20260114_002_008_Cycling_Mountain_EdgeMtb_….fit` → sport 2,
   sub_sport 8). Those identifiers are an oracle independent of the
   implementation; the spec uses a hand-reviewed table of representative paths.
   A small number of older filenames do not carry identifiers and are covered
   only by the structural checks.
5. **`AllFitMessageTypes.fit` survives.** The decoder traverses every SDK
   message type without crashing, even though it interprets almost none of
   them.

Nothing from the corpus enters the repository, so it creates no redistribution
obligation.

### 9.3 Other coverage

- Service: `Workouts::Importer` with FIT uploads — success, `import_format`,
  blob content type and filename, detected versus fallback sport, duplicate
  handling, rollback compensation.
- Archive: `.fit`, `.fit.gz`, ZIP mixing `.gpx` and `.fit`, ZIP of `.fit` only,
  `.gpx.gz`/`.fit.gz` members, and archives with neither.
- Job: batch of mixed formats, per-entry status, cancellation.
- Request: single-file FIT upload success and each validation error, owner-only
  download with the right content type, both locales.
- Model: `import_format` inclusion, and the database check constraint rejecting
  an unknown value.
- Real corpus: all activity files at the pinned revision, representative
  no-track outcomes, filename-based sport oracles, real heart-rate/cadence/
  power propagation through analysis and point serialization, and the
  all-message traversal file.

### 9.4 Browser verification

There is no general JavaScript test suite, so Playwright against
`http://rails:3001` is the only end-to-end check. Verify: single FIT import and
redirect; a real corpus FIT combined with a GPX in a mixed ZIP; a real
`.fit.gz` source; batch progress; map and elevation profile on a FIT workout;
splits; route image; original-file download; light and dark themes; Turbo
navigation away and back; and a clean browser console, discounting the known
Vite HMR and basemap sprite noise documented in `AGENTS.md`.

## 10. Limitations

- **Duplicate detection is byte-level.** `Workouts::Importer#digest_upload`
  hashes raw upload bytes. The same effort imported as both a `.fit` and its
  `.gpx` export produces two different digests and two workouts. A semantic
  fingerprint — started-at plus rounded distance plus start coordinate — is
  separate work.
- **Recorded laps are stored, not used as splits.** Native lap boundaries would
  be a better source for the splits than the current distance-based
  `Allure::Gpx::Splits`, and multi-sport sessions would need a data model that
  does not exist. Both belong to the segments and routes work
  (`[devdoc:segments]`).
- **A positioned recording recomputes its metrics from coordinates.** Device
  distance and speed are read only for a positionless recording, so a FIT and a
  GPX of the same positioned effort report the same numbers.
