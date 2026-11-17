# Strava archive contract

The ZIP Strava sends an athlete who requests their data, imported with what
the athlete wrote on Strava, not only what the files hold. It needs no Strava
account link, no API application and no network access. This document defines
the source, the reading bounds, the sport mapping, the texts and gear, the
job, the manual entries, the photos, the deduplication and the negatives.

## 1. Intent and decisions

1. A dedicated source, `Allure::ImportSources::STRAVA_ARCHIVE` (`key:
   "strava_archive"`, the new kind `:archive`, icon `brand-strava`), always
   enabled. An archive can still go through the file source, which ignores
   its CSV files.
2. One batch per archive: `WorkoutImportBatch.source = "strava_archive"`,
   `trigger: "manual"`, processed by `Workouts::StravaArchiveImportJob`. The
   fallback sport is optional.
3. An archive is history: every import is `bulk: true`, never published
   automatically (`AUTO-PUBLISHING.md`).
4. Nothing leaves the instance, imported workouts and photos stay
   unpublished, and only `activities.csv`, `activities/`, `bikes.csv`,
   `shoes.csv` and — while photos are on — the `media/` photos the CSV names
   are read.

## 2. What the archive holds

- `export_<athlete id>.zip` with `activities.csv`, `activities/` (the
  **original uploaded files**: `.fit.gz`, `.gpx`, `.gpx.gz`, `.tcx`, `.tcx.gz`),
  `bikes.csv`, `shoes.csv`, `media/` (photos), `profile.csv`, `routes/` and
  about twenty other CSV files.
- `activities.csv` is written in the athlete's display language: the headers,
  the activity types and the dates are localized. Numbers use a dot.
- The column order has been stable; new columns are appended at the end, and
  some header names repeat. Archives older than the private notes lack the
  private-note column.
- `Filename` names the upload, not the activity: its number is the upload id.
  An activity typed in by hand has an empty `Filename`.
- `Activity Gear` is the gear's display name; `bikes.csv` and `shoes.csv`
  start with name, brand and model. A nameless item is « brand model » in
  `activities.csv`.
- The last column lists the activity's photos; `media.csv` gives each photo's
  caption, name first and caption second. The archive may list photos it does
  not ship.

## 3. Reading the archive

`Workouts::StravaArchiveReader` (a subclass of `Workouts::ArchiveReader`, for
its path, size, compression-ratio and gzip guards) opens the ZIP from its
path, finds `activities.csv` at the root or under one top-level folder (an
archive unpacked and zipped again), reads the three CSV files (50 MB each at
most) and extracts one `activities/…` member at a time on demand, gzip members
decompressed and sniffed by `Allure::ImportFormat`, and one named `media/…`
photo at a time (§8). The generic reader's 1 000-member cap and 2 GB
uncompressed total do not apply, since an archive holds every photo too: no
member is extracted unless the CSV names it, each is discarded after its
import, the 25 MB member cap and the ratio guard still hold, and the rows are
capped at 10 000. The archive's own bounds are:

- the archive itself, at most 2 GB (`Allure::StravaArchive::MAX_BYTES`), the
  file source keeping 500 MB;
- at most 100 000 entries declared by its central directory, read from its end
  records by `Allure::ZipDirectory` before rubyzip builds one object per
  entry (`too_many_entries`);
- at most one `activities/…` track file per possible activity, 10 000, so
  discovery creates at most one row per CSV row and per unnamed file;
- at most 20 photos per activity (`Allure::Photos::Config::MAX_PER_WORKOUT`),
  the names past it never extracted;
- at most 20 GB extracted over a run, CSV files, tracks and photos together
  (`total_too_large`); once spent, every later member is refused before it is
  read.

`Allure::StravaArchive::Activities` reads `activities.csv` **by position**,
never by header text, and recognises the current and legacy layouts by their
values. A row whose ID is not a number refuses the file
(`malformed_strava_activities`); a ZIP without `activities.csv` is
`not_strava_archive`.

## 4. Sport

`Allure::StravaArchive::ActivityTypes` maps the type label, normalised
(accents and punctuation dropped), through a table of the API names, the
English labels and the French and German labels; any other label must equal an
alias of `Allure::ActivityTypeCatalog` exactly. Nothing matches by substring.

| Strava | Allure |
|---|---|
| Ride, Handcycle, Velomobile | `cycling` |
| GravelRide | `cycling_gravel` |
| EBikeRide | `cycling_electric` |
| MountainBikeRide / EMountainBikeRide | `mountain_biking` / `mountain_biking_electric` |
| VirtualRide / VirtualRun / VirtualRow | `cycling_virtual` / `running_virtual` / `rowing_virtual` |
| Run / TrailRun | `running` / `trail` |
| Walk / Hike / Snowshoe | `walking` / `hiking` / `snowshoes` |
| AlpineSki / BackcountrySki / NordicSki / Snowboard | `skiing_alpine` / `skiing_touring` / `skiing_cross_country` / `snowboarding` |
| IceSkate / InlineSkate | `ice_skating` / `inline_skating` |
| Swim | `open_water_swimming`, `pool_swimming` without position |
| Rowing, Kayaking, Canoeing, StandUpPaddling, Windsurf, Tennis | `rowing`, `kayaking`, `canoeing`, `standup_paddleboarding`, `windsurfing`, `tennis_outdoor` |
| WeightTraining | `strength_training` |
| Workout, Crossfit, HIIT, Elliptical, StairStepper, Yoga, Pilates | `fitness` |

The mapped sport is passed to `Workouts::Importer` as `declared_sport:`.
`Workouts::SportResolver` lets a declaration outrank the file's detection,
with two refinements (`SportResolver::REFINEMENTS`): the file may name one of
the declaration's variants (`Sport::DEFAULT_TARGET_SLUGS` for the generic
sports, the other venue for a swim), and a generic sport still left takes the
account's default variant (`/settings/sports`). A swim recorded without any
position is a pool swim. The entry records `sport_source: "declared"`, which
`Workouts::RebuildJob` never re-detects, like `manual`. An unmapped type uses
the file's own detection, then the batch's fallback sport, else the entry is
`skipped` (`unsupported_sport`).

## 5. Texts, commute and gear

- `title` ← the activity name (255), `description` ← its description
  (10 000), `notes` ← the private note (500, owner-only), `commute` ← the flag,
  OR the file's own `commuting` hint as for any import.
- `Workouts::StravaArchiveGear` matches `Activity Gear` against the account's
  equipment by label, ignoring case, on its first 50 characters, and creates
  what is missing, active: its type from `bikes.csv` (`bike`) or `shoes.csv`
  (`shoes`), else from the declared sport's family (ride → `bike`, run and
  hike → `shoes`), else `misc`; its description « brand model ». A nameless
  item of the CSV is matched by that « brand model ». It carries no
  `external_id` and no connection: the pair is `ImportConnection`'s. The entry
  records `created_equipment`, which the batch page lists. Inactive equipment
  matches but is never attached (`Equipments::Totals`).

## 6. The job

`Workouts::StravaArchiveImportJob` (queue `default`, one archive at a time per
account through `limits_concurrency`) opens the attached archive once, then:

- **discovery** (only while `discovered_at` is unset): one entry per CSV row,
  in CSV order — `source_key: "strava:<activity id>"`, `source_name` the
  activity name (or « Activité %{id} »), `source_path` the `Filename`,
  `external_id` the Strava id, `metadata` the row's facts (`strava_id`,
  `date`, `name`, `type`, `description`, `private_note`, `commute`, `gear`,
  `filename`); then one entry per track member of `activities/` no row names
  (`strava-file:<member>`, imported from the file alone);
- **processing**: each `queued`/`processing` entry in order, stopping at a
  cancellation. A row without a file becomes a manual entry (§7); a row
  whose member the archive lacks is `skipped` (`no_file`); a refused member
  fails its entry only.

A retry resumes at the first unfinished entry. An entry an interrupted run
left `processing` after its workout was committed meets that workout as a
duplicate: it claims it back as `imported` (`Workouts::ImportResumption`: the
entry was already `processing`, the workout is younger than the entry, no
other entry holds it), with `declared` or `fallback` provenance again (a
detected sport is not recorded) and its photos attached unless the workout
already holds some. The file and remote batch jobs share the rule. A ZIP that
is not a Strava archive fails the batch with the translated reason.

When the batch ends `completed` or `failed` — never `cancelled` — the account
gets one mail, `ImportMailer#strava_archive_finished`, in its locale: the
counts, the photo counts when there are photos, that maps, places and
segments keep filling in and stay private, or the failure's reason; and a
link to the batch page. A deactivated account gets none. No other import
mails, and no in-app notification is added.

## 7. Manual entries

A row without a file is an activity the athlete typed in on Strava. It
becomes a manual entry (`MANUAL-ENTRY.md`) through
`Workouts::StravaArchiveManualEntry`, which calls `Workouts::ManualEntry`:

- the start is `Activity Date`, read by `Allure::StravaArchive::Dates` in UTC
  whatever the language — an ISO date, a numeric day-month-year (day first; a
  first number over 12 settles it), a month name in English, French, German,
  Spanish, Italian, Dutch or Portuguese, or a year-first date — then the last
  clock time and an afternoon marker (`PM`, `下午`, …). An invalid date is
  nil, never rolled over; the entry then fails with « Date Strava illisible ».
- the figures come from the SI block after the file column, at the same
  offsets in both layouts (`Activities::FIGURE_OFFSETS`): elapsed and moving
  time, distance, ascent, maximum and average heart rate, average power,
  calories; the leading `Elapsed Time` is the fallback duration, the leading
  `Distance` (localized, in km) is never read. Only these rows keep their
  figures in the entry metadata.
- a figure a manual entry refuses — outside `Workout::MANUAL_LIMITS`, an
  ascent for a sport that measures no elevation, a maximum heart rate under
  the average — is left out instead of refusing the activity; a missing
  duration fails the entry. The moving time never exceeds the duration.
- the sport is the declared one, refined only by the account's default
  variant (there is no file to refine it), else the batch's fallback
  (`fallback`), else the entry is `skipped` (`unsupported_sport`).
- the name, description, private note, commute flag and gear apply as for a
  recording; an entry already starting within the window (§9) among the
  account's authored workouts is the same activity, imported before.

## 8. Photos

The last column of `activities.csv` lists an activity's photos,
`|`-separated (`media/<name>.jpg`); `Activities` keeps the plain names,
always under `media/`, and discovery stores them as the entry's `media`.
Once an entry has **created** its workout — a recording or a manual entry,
never a duplicate — and while `Allure::Photos::Config.enabled?`, each listed
photo is extracted (`StravaArchiveReader#extract_media`, path and ratio
guards, cut one byte past the photo cap) and handed to
`Workouts::PhotoUpload`, the owner's own seam: its type, size, 20-per-workout
and quota checks apply, and `PhotoProcessJob` makes the stripped copies and
places the photo along the route by its EXIF (`PHOTOS.md`). Its `media.csv`
caption (`Allure::StravaArchive::MediaCaptions`, by position) is set, cut to
the photo caption limit. A photo the archive lacks is counted as
`photos_missing`, a video or a photo the seam refuses as `photos_refused`;
neither fails the entry, and the batch page sums all three. The photos stay
private like any owner photo, and a publication shares them only through the
publish form's own choice.

## 9. Deduplication

In order: the SHA-256 digest of the decompressed member against the account's
workouts (Strava keeps the original bytes, so a ride already imported from a
remote connection or as a file matches); then `Workouts::Importer`'s
`near_duplicate_window:` (120 s), checked after the analysis and before
anything is stored, against `user.workouts.recordings` — the file's own start
time, never the CSV's localized date. The duplicate entry names the existing
workout. Importing the same archive again creates no workout and no
equipment. Only this source passes the window today.

## 10. Interface

- The tab « Archive Strava » / « Strava archive » follows « Fichiers ». The
  `import-source` controller treats the `archive` kind like `remote`: the
  shared options card and the footer submit hide.
- The panel (`workout_imports/sources/_strava_archive.html.erb`) sits in the
  upload form with fields of its own names (`strava_archive`,
  `strava_sport_id`) and submits through its button's `formaction` to `POST
  /workout_imports/strava_archive` (`StravaArchiveImportsController#create`),
  which refuses a missing file, anything but a `.zip`, and an archive over
  2 GB, returning to the panel (`@initial_source`). It then asks
  `Workouts::ImportAdmission`: one archive queued or running per account,
  and the account's 6 GB daily upload budget (`IMPORT-SOURCES.md`). The
  archive is purged once its batch ends.
- The batch page shows the source badge, « Lecture de l'archive Strava… »
  before the entries exist, and « Équipement(s) créé(s) : … ». Copy:
  `DESIGN.md` §19.36 and §20.5.
- `POST /api/rest/v1/imports` with `source=strava_archive` takes one archive
  in `files[]` (`trigger: "api"`), the same checks answered as
  `validation_failed` (`one_archive`, `not_zip`, `too_large`, an unknown
  `fallback_sport`); `fallback_sport` is optional and `notes` ignored
  (`API.md`).
- `/admin/imports` and `allure_import_batches{source}` pick the source up from
  `WorkoutImportBatch::SOURCES`.

## 11. Negatives

- No follower, comment, kudo, segment, route, profile or other CSV is read,
  nor a `media/` file the CSV does not name; nothing is fetched from Strava;
  no `ImportConnection` is created.
- No photo is attached to a workout the archive did not create.
- No imported workout is published, automatically or otherwise.
- No coordinate or file content enters the entry metadata; a manual row's
  figures do, since they are what it is built from.

## 12. Tests

- `spec/lib/allure/strava_archive/` — the dates in eight languages and the
  refusals, the SI figures and the `Media` names, the current, legacy and
  German layouts, appended columns, a byte order mark, multi-line
  descriptions, the row cap, the type table and its catalog fallback, gear by
  header and by position. Every CSV is synthetic
  (`spec/support/strava_archives.rb`).
- `spec/jobs/workouts/strava_archive_import_job_spec.rb` — texts, declared
  sports and provenance, the default variant, orphans, a missing member, a
  row without a file made a manual entry, an unreadable date, an unsupported
  type with and without a fallback, photos attached and refused (none on a
  duplicate nor while photos are off), gear created and matched, a re-import,
  the near-duplicate window, a ZIP that is not an archive, cancellation,
  resumption.
- `spec/services/workouts/sport_resolver_spec.rb` and `importer_spec.rb` —
  the declaration and the window; `spec/requests/workout_imports_strava_archive_spec.rb`
  — the panel, the endpoint, its refusals, the batch page;
  `spec/requests/api/rest/v1/imports_spec.rb` — the API archive and its
  refusals, against the OpenAPI document.

## 13. Deferred

- A completion notification for a multi-hour import.
- `routes/` as courses.
