# Photos contract

An owner attaches photos to a workout; Allure places them along the route, a
publishing profile shares a frozen, sanitized copy of them, and storage is
bounded per account. This document defines the data model, the quota, the
intake and processing, the placement, the publication copies, the surfaces and
the tests. Federation and the REST, webhook and MCP photo surfaces are deferred
(§9).

## 1. Scope and decisions

- **Photos only.** Videos, GIF animation and Live Photos are out of scope; a
  GIF is refused.
- **Originals are kept, owner-only.** The uploaded bytes are stored unchanged
  (EXIF included) and served only to the owner (download, export). Every other
  surface reads a re-encoded, metadata-free derivative.
- **Publications freeze their photos.** Publishing copies the selected photos
  into the publication as new sanitized blobs. Adding, deleting, recaptioning
  or moving a photo later never changes an existing publication; the owner
  republishes, as for route images (`DERIVATIONS.md`).
- **Per-account quota.** Each account has a photo storage quota (instance
  default plus an operator override); uploads beyond it are refused.
- Photos are additive: they never change a metric, a record, an effort, a
  derivation marker or the analysis.

## 2. Data model

### 2.1 `workout_photos`

| Column | Type | Notes |
|---|---|---|
| `id`, `uuid` | bigint PK, uuid unique | public id is the UUID's ShortUUID (`WORKOUT.md`) |
| `workout_id` | bigint FK, cascade | |
| `user_id` | bigint FK, cascade | denormalized owner, for scoping and quota |
| `position` | integer ≥ 0 | gallery order, unique per workout (deferrable) |
| `caption` | text ≤ 500 | plain text; also the alt text |
| `status` | `processing` / `ready` / `failed` | |
| `failure_reason` | string | translated key, never a library message |
| `original_content_type` | string | `image/jpeg`, `image/png`, `image/webp`, `image/heic` |
| `width`, `height` | integer | after orientation |
| `taken_at_local` | datetime | EXIF camera wall clock (digits kept, no zone), nullable |
| `taken_at_utc_offset` | integer (s) | the file's `OffsetTimeOriginal`, nullable; never infer UTC from a wall clock |
| `exif_location` | geography(Point) | as read from the file, owner-only, nullable |
| `location` | geography(Point) | the placement in use, owner-only, nullable |
| `location_source` | `exif` / `time` / `manual` / `none` / `cleared` | `cleared` is the owner's removal |
| `track_distance` | float (m) | along the workout, nullable |
| `track_elapsed` | float (s) | from the workout start, nullable |
| `bytes_total` | bigint | original + derivatives, the quota unit |
| timestamps | | |

Constraints: `workout_id`, `position` unique; `caption` length; `location`
null exactly when `location_source` is `none` or `cleared`, and then without
`track_distance`/`track_elapsed`; `bytes_total ≥ 0`;
at most `Photos::MAX_PER_WORKOUT` (20) rows per workout, enforced under a
row lock on the workout (model validation plus the service's lock).

Attachments (`has_one_attached`, `dependent: :purge_later`):

- `original` — the uploaded bytes, unchanged;
- `display` — WebP, longest side ≤ 2048 px, quality 82, `strip: true`;
- `thumbnail` — WebP, longest side ≤ 480 px, `strip: true` (cards crop
  through CSS `object-fit`, never in the file).

`workouts.photo_time_offset_seconds` (integer, default 0, bounded ±14 h)
holds the owner's camera-clock correction for the workout (§4).
`workouts.photos_ordered_by_owner` (boolean, false by default) records that
the owner reordered the gallery by hand; until then the order follows the
capture time (§4.1).

### 2.2 Quota

- `PHOTOS_QUOTA_MB` (default `2048`) is the instance default, read at call
  time by `Allure::Photos::Config` beside `PHOTOS_ENABLED` (default `true`;
  while false, no photo surface renders and uploads answer 404).
- `users.photo_quota_bytes` (nullable bigint) overrides it per account; `0`
  disables uploads for that account. Only the operator sets it, from
  `/admin/accounts/:id` (audited `photo_quota_changed`).
- Usage is `SUM(workout_photos.bytes_total)` for the account (indexed on
  `user_id`); no cached counter.
- Publication copies (§5) are **not** counted: they are bounded by the photo
  count of a live publication and purged when it is withdrawn.
- All usage-changing writes lock the account, then the workout or photo.
  Intake reserves the original's byte size, including while processing.
  Derivatives are charged under the same account lock; insufficient space
  leaves the original and a failed photo (`quota_exceeded`), never an
  unaccounted overrun. The owner may free space and retry.
- An upload that would exceed the quota is refused before processing with a
  message naming the usage and the quota; the settings page and the photo
  card show the usage bar.

## 3. Upload and processing

### 3.1 Intake (`Workouts::PhotoUpload`)

`POST /workouts/:id/photos` (owner-scoped through `current_user.workouts`,
multipart, several files) — one file per request from the Stimulus uploader so
each shows its own progress and error. Every workout shape may carry photos:
recordings, positionless recordings, manual entries; a credit row may not
(read-only, `SHARED-ACTIVITIES.md`).

Checks, in order, before anything is stored:

1. feature enabled, account active, workout below 20 photos;
2. size ≤ `Photos::MAX_BYTES` (20 MB) and non-empty;
3. quota: usage + incoming size ≤ quota (the derivatives must also fit after
   processing; no tolerance past the line);
4. real type from the bytes (JPEG `FF D8 FF`, PNG signature, `RIFF….WEBP`,
   ISO-BMFF `ftyp` with `heic`/`heix`/`mif1`); the declared type and the
   extension are ignored;
5. HEIC only while the image's libvips reports a HEIF loader
   (`Allure::Photos::Config.heic_supported?`); otherwise refused with its own
   message (Safari already converts most iPhone picks to JPEG).

The row is created `processing` with its `original` attached, then
`Workouts::PhotoProcessJob` is enqueued after commit.

Remote import sources attach photos through the same intake: the Strava
archive's `media/` photos ([STRAVA-ARCHIVE.md](STRAVA-ARCHIVE.md)) and a virtual platform's
activity snapshots (`REMOTE-IMPORTS.md`). They arrive unplaced, since the game
writes no EXIF, and the owner places them from the map.

### 3.2 Processing (`Workouts::PhotoProcessJob`, queue `photos`)

The `photos` queue runs on the default worker with concurrency 2 (vips is
memory-hungry). Steps:

1. open the original with libvips (`fail: true`), refuse beyond 12 000 px on
   a side or 100 megapixels (decompression bomb guard);
2. read EXIF through `Allure::Photos::Exif` (pure, from the vips `exif-*`
   fields): `DateTimeOriginal`, `OffsetTimeOriginal`, GPS latitude/longitude
   with their references; malformed values are ignored, never fatal;
3. `autorot`, then build `display` and `thumbnail` with
   `ImageProcessing::Vips` (`resize_to_limit`, `sharpen: true`, `convert
   "webp"`, `saver(strip: true)`), the same chain as `Users::AvatarUpload`;
4. store width, height, `bytes_total`, `taken_at_local`,
   `taken_at_utc_offset` and `exif_location`, and mark it `ready`;
5. place it (§4); a placement failure leaves a ready, unplaced photo.

A failure marks the row `failed` with a translated reason; the owner retries
or deletes it. `Workouts::PhotoRecoveryJob` (recurring) re-enqueues rows stuck
in `processing` for more than 10 minutes. Nothing here is a derivation with a
version marker: a photo is processed once.

### 3.3 Editing and deletion

`PATCH /workouts/:id/photos/:photo_id` (caption, position, placement),
`DELETE` (purges the three blobs), `PATCH /workouts/:id/photos/order` (the
whole order in one request, which marks the order as the owner's), and
`PATCH /workouts/:id/photos/sort` (resume the automatic order). Deleting a
workout deletes its photos (`Workouts::WorkoutDeletion`, bulk deletion,
account purge). None of these touch a publication.

## 4. Placement along the route (pure, `lib/allure/photos/`)

`Allure::Photos::Exif` reads the capture wall clock, its offset and the GPS
position from the libvips `exif-ifd*` fields while the photo is processed
(before stripping). `Allure::Photos::Placement` takes the recording segments'
stored points and answers a position, a source, a distance and an elapsed
time; `Workouts::PhotoPlacement` applies it:

1. **`exif`** — the EXIF position, kept as is when it lies within 200 m of
   the recorded track (nearest recorded stretch, within one recording
   segment); its distance and elapsed time are those of its projection on the
   line. A position further away stays in `exif_location`, unused.
2. **`time`** — otherwise the capture instant: the wall clock minus the
   file's `OffsetTimeOriginal`, or read in the account's time zone when the
   file states none, plus the workout's `photo_time_offset_seconds`. It is
   interpolated along the recording between 5 minutes before the start and
   5 minutes after the end; inside a pause between recording segments the
   photo sits where the previous segment ended.
3. **`manual`** — the owner arms « Placer sur le parcours » and clicks the
   map; the click snaps onto the nearest recorded stretch, refused beyond
   2 km. On a route that passes the same place twice the nearest stretch
   wins; the owner moves the photo again if it chose the other pass.
4. **`none`** — no usable position (positionless or manual workout, no EXIF,
   out of window).
5. **`cleared`** — the owner removed the position (« Retirer la position »).

`manual` and `cleared` are the owner's and are never overwritten;
« Placer automatiquement » hands a photo back to the automatic sources.
Saving the camera-clock correction (« Correction de l'horloge de l'appareil
photo », minutes within ±840) re-places every automatic photo at once, and a
re-analysis (`Workouts::Reanalyzer`) enqueues `Workouts::PhotoPlacementJob`
on the `photos` queue whenever the workout has photos.

### 4.1 Gallery order

Until the owner reorders the gallery by hand, `Workouts::PhotoOrder` keeps it
in capture-time order: the instant `Workouts::PhotoPlacement#capture_time`
derives (the file's offset or the account's zone, plus the camera correction),
then — for a photo that recorded no time but sits on the route — its position
along the recording, then the upload order for what is left. The order is
reapplied after processing, placement, a clock correction and a re-analysis,
under the workout lock; the deferred unique constraint lets every position be
rewritten in one transaction. A manual reorder sets
`workouts.photos_ordered_by_owner`; « Trier par heure de prise de vue » clears
it and sorts again. A publication keeps the order it froze.

### 4.2 Why a photo is not on the route

`Allure::Photos::Placement#diagnose` explains an automatic placement that
found nothing, for the owner's page: an EXIF position further than 200 m from
the track (its distance), and/or a capture time more than five minutes before
the start or after the finish (the gap). A photo with neither clue says so.

## 5. Publishing (frozen copies)

### 5.1 Profile settings

Three new keys in `PublishingProfile::SETTING_KEYS`, all booleans, all **off
by default** for every profile, existing and new:

- `photos` — share the selected photos;
- `photo_captions` — share their captions (otherwise a generic alt text);
- `photo_positions` — share where each photo sits along the shared route
  (requires `photos` and a shared track).

### 5.2 Selection and privacy

The publish and replace forms list the ready photos with a checkbox each
(hidden `photo_selection` marks that a list was shown, so unticking them all
shares none) only when the selected profile shares photos; a profile that
shares none gets a sentence saying so and a link to the profiles instead.
`Workouts::PublicationPhotoSelection` decides, for a profile whose `photos`
setting is on:

- **sensitive** — the photo's placement or its EXIF position lies inside an
  active privacy zone (`ZoneFilter#covered?`). It starts unticked with the
  §19.35 badge and notice. Without an explicit choice (`photo_ids: nil`:
  automatic publishing, the REST API) it is left out. An explicit choice that
  includes it needs `photos_acknowledged`, else the publish is refused with
  `photos_unacknowledged`; it is then shared **without any position**.
- **unplaced** — shared without position; the form says the image itself can
  reveal where it was taken.
- **placed** — shared with a position only when `photo_positions` is on.

A shared position is never a coordinate. It is the distance, in metres
rounded to 0.1, of the nearest **published** point to the photo's placement,
measured over the published points in order (a gap between published
segments adds nothing), so a receiver measures it again from the same
geometry (`Allure::Photos::RouteDistance`). A photo whose nearest published
point lies further than 200 m loses its position. Captions are shared only
with `photo_captions`.

### 5.3 Snapshot

- `representation["photos"]`: an ordered array of
  `{ "id", "width", "height", "caption"?, "distance"? }`, at most 20, checked
  by `WorkoutPublication#validate_photos` (no other key, no coordinate).
- `workout_publication_photos` rows: `uuid` (the `id` above),
  `workout_publication_id` (cascade), `position`, `width`, `height`,
  `caption`, `distance`, with `display` and `thumbnail` attachments; every
  column is read-only once written.
- The copies are made **at publish time, in the request**, by
  `PublicationCandidate` from the owner's already stripped `display` file,
  bounded again (display ≤ 1600 px, thumbnail ≤ 480 px) and encoded without
  metadata (`Allure::Photos::Processor.publication_copies`); the snapshot
  records their measured size. They are new blobs, never the owner's, so
  editing or deleting a workout photo leaves the publication intact. Being
  synchronous, they need no `preparing` gate: a scheduled publication has
  them from the start. A copy that cannot be made refuses the publish with
  `photos_unavailable`.
- Automatic publishing waits for every photo of the workout to leave
  `processing` (`AutoPublicationReadiness` `photos` check; the processing job
  re-runs a waiting automatic publication) and takes every ready,
  non-sensitive photo.
- `Workouts::PublicationCleanup` purges the copies with the rest of the media
  once a withdrawn publication's federation work is terminal; the redacted
  snapshot carries no `photos`.

### 5.4 Reading

Members-only, through `Workouts::PublicationResolver` and the
`PublicationPolicy` `photos` resource (the snapshot's `photos` setting and
array, regardless of the profile's current setting):

- `GET /publications/:id/media/photos/:photo_id?variant=thumbnail` (display
  by default) for the browser, `private, no-store`;
- the publication page (and the owner's reader preview) shows a read-only
  gallery card opening the same lightbox, with no original download, and,
  when distances are shared, thumbnail markers on the published map at the
  published point each distance names. The profile carries no photo pills
  for readers: the chart's distances are the recording's, not the published
  route's;
- feed and profile cards show the first three thumbnails and a « +N ».

## 6. UI

- **« Photos » card** on the workout page, after the analysis card and before
  comments: the count, « Ajouter des photos » and « Gérer », the §19.34 line,
  the intake zone (a labelled picker button, `accept="image/*"`, multiple, and
  the obvious refusals answered before sending) and a compact grid of the same
  thumbnails readers see. The whole card accepts a drop. A processing tile
  shows a spinner; a failed one keeps « Réessayer » and « Supprimer ». The
  quota appears only from 80 % of the account's storage; the manager always
  shows it. The gallery refreshes by morphing its Turbo frame, so a caption
  being typed and an open viewer survive.
- **`/workouts/:id/photos` — the manager** (`DESIGN.md` §20.24): the route as a
  sticky rail from `lg`, the manager beside it, one row per photo with the
  drag handle, the thumbnail, the self-saving caption, the capture time, the
  placement line and the reason an automatic placement found nothing (§4.2),
  then « Placer sur le parcours » and a `⋯` menu (remove the position, place
  automatically, move up/down, download the original, delete). The camera
  clock, « Trier par heure de prise de vue » and the quota live here. A marker
  click highlights its row; a placement returns to the row it started from.
- **Lightbox**: a native `<dialog>` Stimulus controller (`photo-lightbox`) on a
  dark surface in both themes — arrows, `Esc`, swipe, focus trap through the
  dialog, a counter of the photo's place in the set, caption as visible text
  and `alt`, capture time and distance along the route, « Voir sur la carte »
  when placed; no library.
- **Map**: thumbnail markers (circular, 36 px, primary ring), clustered with a
  count when they overlap at the current zoom; a click opens the lightbox;
  owner-only « Déplacer » drag mode snapping to the track. The placement
  instruction and its error are shown on the map itself, with « Annuler ».
  Markers and listeners are released on disconnect (Turbo rules).
- **Elevation profile**: a camera pictogram pill at each placed photo's
  distance, following the existing marker vocabulary (`SMART-LAPS.md`), hover
  synchronized with the map.
- **Cards and lists**: up to three thumbnails on timeline and feed cards; a
  camera count column in the table view.
- **Original download**: the lightbox `⋯` offers « Télécharger l'original »
  to the owner only.
- **Privacy copy** (§19 additions): the publish dialog's photo list, the
  sensitive-photo sentence, the « une photo peut révéler un lieu » warning,
  and the shared / not-shared list pair gains « Photos (N) » and « Position
  des photos ».

Every string ships in `fr.yml` and `en.yml`. The iOS companion uses the same
web card (the WKWebView file input opens the photo library); a native picker
bridge is out of scope.

## 7. Programmatic surfaces

- **Export** ([ACCOUNT.md](ACCOUNT.md)): `photos/<workout id>/<photo id>.<ext>`
  originals plus `photos/index.json` (caption, order, placement). Photos are
  not re-imported.
- **Admin and metrics**: `/admin/accounts/:id` shows usage and the override;
  `/admin` system diagnostics show total photo storage; `/metrics` exports
  `allure_photos{status}` and `allure_photo_bytes`.

## 8. Tests

- `Allure::Photos::Exif` and `Placement` units (EXIF rationals and
  references, missing offset, window edges, pauses, multi-segment tracks,
  200 m threshold, re-placement after an offset change).
- `Workouts::PhotoUpload`: magic numbers, size, count under concurrency,
  quota (default, override, zero), HEIC gating.
- `PhotoProcessJob`: orientation, stripped derivatives (no EXIF in `display`
  or `thumbnail`), bomb guard, failure path, recovery.
- Request specs: owner-only original and derivatives (404 for everyone else),
  members-only publication photos, no raw storage URL anywhere.
- Publication: selection and sensitivity, acknowledgment, frozen copies
  survive photo and workout deletion, purge on withdrawal, auto-publishing
  readiness.
- Export archive, account purge, metrics catalog guard.

## 9. Deferred

- **Federation of photos**: `Image` attachments of the workout Note, the
  inbound parser and attachment model, the verifier and re-encoding, the
  received-note gallery and the ring phases.
- **REST, webhooks and MCP**: the `/workouts/{id}/photos` endpoints, the
  `workout_photo.created` and `workout_photo.deleted` events, and the photo
  fields of `get_workout_context`.
- **`allure_publication_photo_bytes`**: the publication storage gauge.

## 10. Out of scope

- Videos, GIF animation and Live Photos.
- A native photo picker bridge in the iOS companion.
- Per-photo operator moderation of a received or local publication; the
  operator withdraws the publication.
- Photos from Garmin Connect.
- Re-importing photos from the account export.
