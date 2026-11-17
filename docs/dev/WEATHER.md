# Weather contract

Allure enriches a recorded workout with the historical weather met along its
route, derives the wind the athlete actually faced, lets the owner share a
summary through a publishing profile, and lets another Allure instance receive
it. This document defines the provider, the sampling and analysis, the data
model, the pipeline, the publication, the surfaces and the device temperature.

## 1. Scope and decisions

- **Provider**: Open-Meteo only. No provider abstraction, no other API.
- **Two-level opt-in**, like terrain elevation (`ELEVATION.md`):
  - the instance offers the feature only while `WEATHER_ENABLED=true`;
  - every account additionally carries `users.weather_enrichment_enabled`,
    **default `false` for every account**, existing and new. Off means no
    coordinate or timestamp of that account ever leaves the instance for
    weather.
- **Hourly series along the route**, not one point: the position at each hour
  of the activity plus departure and arrival, one request per workout in the
  ordinary case.
- **Wind analysis**: the wind component along the direction of travel,
  classified head / tail / cross, distance-weighted over moving time, per split
  and over the whole workout.
- **Coarsened requests**: coordinates are rounded to 0.1° (~11 km) before they
  leave; the recorded elevation is sent beside them so the provider's
  elevation downscaling stays right in the mountains.
- **Federation in the first draft**: a publishing profile's `weather` setting
  (off by default) freezes a summary into the snapshot and announces it as
  Note tags, parsed by remote Allure peers. The hourly series never leaves the
  owner.
- Weather is additive: it never changes a metric, a record, a segment effort,
  or an existing publication.
- Opting out stops every future request immediately. Existing data stays until
  the owner presses « Supprimer la météo enregistrée » on the settings page,
  which deletes the rows and clears `weather_start`/`weather_end`.
- A credit row gets no weather of its own: its shape forbids it. Its page
  shows the source's weather summary only through the source's publication the
  participant may read, and only when that publication shares weather — the
  same read-through as the source's map. Nothing is copied.

## 2. Provider contract

Two endpoints, chosen by the workout's start:

| Start | Endpoint | Data |
|---|---|---|
| on or after `WEATHER_FORECAST_SINCE` (default `2022-01-01`) | `{WEATHER_FORECAST_URL}/v1/forecast` (default `https://historical-forecast-api.open-meteo.com`) | archived high-resolution model runs (`best_match`), available up to the present |
| before | `{WEATHER_ARCHIVE_URL}/v1/archive` (default `https://archive-api.open-meteo.com`) | ERA5 reanalysis, back to 1940 |

If the forecast endpoint answers with only nulls for the window, the client
falls back once to the archive. The chosen endpoint and model are stored.
There is no later "upgrade" from one source to the other.

Request: `latitude=a,b,…&longitude=c,d,…&elevation=e,f,…&start_date&end_date`
(UTC, `timezone=GMT`), `wind_speed_unit=ms`, `hourly=` exactly these ten
variables (Open-Meteo bills more than ten variables, more than ten locations,
or more than two weeks as several calls):

`temperature_2m, apparent_temperature, relative_humidity_2m, precipitation,
weather_code, cloud_cover, surface_pressure, wind_speed_10m,
wind_direction_10m, wind_gusts_10m`

- At most 10 locations per request; a longer activity is split into several
  requests (counted against the budget).
- `WEATHER_API_KEY` is optional: when set it is sent as `apikey` (commercial
  `customer-*` hosts are configured through the two URLs). The free tier is
  non-commercial; `.env.example` says so.
- A 429 or 5xx is retryable (honouring `Retry-After`); a 4xx otherwise is a
  terminal `failed`.

The client sends `timeformat=unixtime`; a 400 answer, a refused key or any
other 4xx is final, a 429, a 5xx or a transport failure is retried by the job
with exponential back-off (five attempts, then `failed`).

`Allure::Weather::Config` reads every value at call time (`WEATHER_ENABLED`,
the two URLs, `WEATHER_FORECAST_SINCE`, `WEATHER_API_KEY`,
`WEATHER_REQUESTS_PER_SECOND` default 2, `WEATHER_MAX_REQUESTS_PER_DAY`
default 5 000), like `Allure::Elevation::Config`.

## 3. Sampling, series and analysis (pure, `lib/allure/weather/`)

- `Sampler`: from the stored points, the position at the start, at each whole
  UTC hour inside the activity, and at the finish; rounded to 0.1°;
  deduplicated by grid cell (a cell keeps the mean recorded elevation of its
  samples). A workout without timestamps yields no sample (→ `unavailable`).
- `OpenMeteo`: the HTTP client (no Active Record), returning per-location
  hourly arrays.
- `Series`: for every hour of the activity, the values of the cell the athlete
  was in. Wind is interpolated in time through its u/v components (never by
  averaging angles).
- `WindExposure`: for each moving stretch (headings smoothed over ~100 m,
  stopped points excluded with the sport's stopped-speed threshold), the
  relative angle between travel and the wind's origin:
  - **head** within ±45° of ahead, **tail** within ±45° of behind, **cross**
    otherwise;
  - outputs the distance shares (head/tail/cross summing to 1), the
    distance-weighted mean effective headwind (m/s, positive against), and the
    same per split of `Workouts::SplitsService`.
  - It reports the 10 m wind as the provider gives it; no height correction.
- `Conditions`: WMO `weather_code` → a token
  (`clear, mostly_clear, partly_cloudy, overcast, fog, drizzle, rain,
  heavy_rain, freezing_rain, snow, showers, thunderstorm`).
- `Icons`: token → a **Meteocons** file (`@meteocons/svg` and
  `@meteocons/svg-static`, the monochrome style, in `app/views/weather/icons`,
  with their licence files; only the server reads them, and each profile and
  map marker carries both variants as `svg: { animated, static }`), day or
  night variant for the conditions that have one. `Daylight` decides which,
  from the solar elevation at the sample's own hour and rounded cell — the
  provider is asked nothing extra, since an eleventh hourly variable would
  double a billed call. The series rows carry `day`, the summary `is_day` (the
  majority), and both travel in the snapshot and through federation.
- `Summary`: temperature min/max/mean, apparent temperature mean, mean wind
  speed, maximum gust, circular-mean wind origin, total precipitation, the
  dominant condition, and the exposure shares.

The engine stays linear in points (sliding windows only).

## 4. Data model

`workout_weathers`, one row per workout (unique `workout_id`, FK cascade):

| Column | Notes |
|---|---|
| `status` | `pending` / `ready` / `unavailable` / `failed` |
| `fetch_version` | request shape generation (`Workouts::WeatherEnricher::FETCH_VERSION`) |
| `analysis_version` | series/exposure generation, recomputed offline from `responses` |
| `endpoint` | `forecast`/`archive` (the provider's `best_match` names no model) |
| `responses` | raw hourly arrays per cell (jsonb), the only provider bytes kept |
| `samples` | one entry per sample: `t`, `cell`, the cell's rounded `lat`/`lon` and `ele` (jsonb); the reuse key |
| `series` | hourly series along the route (jsonb array) |
| `exposure` | totals and per-split values (jsonb) |
| `summary` | §3 summary (jsonb object) |
| `requests_count`, `fetched_at`, `last_error`, `unavailable_reason` | operations (`untimed`, `no_data`) |

`workouts.weather_start` / `weather_end` become the denormalized projections
(start and finish hour), exactly as `workouts.places` is for the toponymy. The
`workouts_credit_shape` and `workouts_manual_shape` constraints already keep
them `NULL`.

`users.weather_enrichment_enabled` boolean, default `false`, not null.

`publishing_profiles.settings["weather"]`, default `false`, added to
`DEFAULT_SETTINGS` and both setting lists.

## 5. Pipeline (`DERIVATIONS.md`)

- **Eligibility** (`Workouts::WeatherEligibility`): the feature on, the owner
  opted in and not deactivated, `origin: "import"`, `positioned?`, sport not
  `virtual`. A structural refusal (not a recording, positionless, virtual)
  discards any stored row; a consent or feature refusal asks nothing and
  keeps what is stored. An untimed track ends `unavailable: untimed`.
- `Workouts::WeatherRefresh` is the single scheduling seam (like
  `ToponymyRefresh`): marks the row `pending` and enqueues
  `Workouts::EnrichWeatherJob` (default queue, one job at a time on the
  `workout-weather` concurrency key). It is called:
  - after import, deferred like the geocoding while a terrain profile is
    requested (the re-analysis, or the apply job giving up, schedules it);
  - after a re-analysis or trim that moved the start or the timestamps;
  - after a sport change (a change to a virtual sport destroys the row);
  - by `Workouts::WeatherRecoveryJob` (every 15 minutes in production: a
    `pending` row older than 2 h, a `failed` one older than 6 h created in
    the last 2 days);
  - by the owner's « Réessayer » / « Récupérer la météo » on the card
    (`POST /workouts/:id/weather`);
  - by `Workouts::BackfillWeatherJob` (id-cursor, audited on `/admin/jobs`)
    and by `Workouts::UserBackfillJob`'s new `weather` scope from
    `/settings/data` and from the consent page right after opting in.
- The daily budget is the sum of `requests_count` over rows fetched in the
  last 24 h; when it is reached the job raises `BudgetExhaustedError` and is
  retried hourly (24 times), the row staying `pending` for the recovery.
- A change of `analysis_version` only is converged offline from `responses`
  by the same backfill, with no request.
- **Automatic publishing**: `AutoPublicationReadiness` gains a `weather` check,
  required only when the target profile shares weather and the workout is
  eligible; `ready`, `unavailable` and `failed` are settled. The enrich job
  nudges `AutoPublishJob`.
- Account deletion and workout deletion cascade; the export carries the
  status, summary and hourly series inside each workout of
  `workouts/index.json` (the REST representation).

## 6. Publication and federation

- `SanitizedPublicationBuilder` gains `weather:` (the `summary` only) and the
  `weather` representation key, set only when the profile enables it and the
  row is `ready`. The snapshot is frozen like every other key; a later refresh
  never changes it. No series, no cell, no coordinate, no per-split value.
- `Serializers::WorkoutNote#weather_tags` emits `Note` tags:

| Tag | Content |
|---|---|
| `weather_condition` | condition token |
| `weather_temperature` | `min,max,apparent_mean` °C, one decimal |
| `weather_temperature_mean` | mean °C — its own tag, so a peer reading the three-value tag keeps it |
| `weather_humidity` | mean % |
| `weather_precipitation` | total mm |
| `weather_wind` | `mean,gust_max,origin_deg` (m/s, degrees) |
| `weather_wind_exposure` | `head,tail,cross,headwind` (shares to three decimals, m/s) |
| `weather_day` | `day`/`night`, optional |

An empty position is an absent value. `Allure::Weather::NoteTags` is the one
codec both ends use, and `Allure::Weather::Summary.valid?` the one shape check
(the publication and the received note validate their stored `weather` with
it).

- `Parsers::RemoteNote#parse_weather` is strict: unknown condition → dropped;
  temperature in −90…60 with min ≤ max, humidity 0…100, wind 0…100, gusts
  0…150, origin 0…360, shares in 0…1 summing to 1 ± 0.02; a malformed tag is
  skipped with a warning, and a summary invalid as a whole is dropped.
  `Inbox::Create` stores it in the received representation,
  `RemoteNoteView#weather` exposes it.
- The publication page, feed cards and the received note page render the same
  summary partial.
- `dip fed_test` stores a ready weather summary on the published ring workout
  (the ring never reaches Open-Meteo), shares it through the public profile,
  and asserts the parsed representation on the receiving node.

## 7. UI and copy

- **Consent** `/settings/weather` (navigation entry under Settings, only while
  the feature is on): explanation, the switch, the privacy sentence:
  « Allure envoie à Open-Meteo, pour chaque activité, des positions arrondies
  à environ 10 km, leur altitude et les heures de l'activité. Rien n'est
  partagé sans votre accord dans un profil de publication. » / English
  equivalent; then « Récupérer la météo de mes activités existantes ».
- **Workout header**: a badge in the badge row — the condition icon and the
  mean temperature (« ☁ 7 °C », tooltip « Couvert, 7 °C de moyenne »),
  linking to the card. The owner sees it once the weather is ready, a reader
  when the publication shares it; the feed card carries the same badge.
- **Workout page**: the weather card follows the Analyse card (after the
  profile for a reader, who has no analysis) — the Meteocons condition icon,
  animated, in the brand primary on a primary-tint tile (static under
  `prefers-reduced-motion`: the server inlines both and CSS shows one),
  « 12–18 °C », « ressenti 11 °C », wind
  « 15 km/h SO, rafales 32 km/h » with an arrow, precipitation when > 0, and
  the exposure bar « De face 42 % · De côté 27 % · De dos 31 % ».
  States: pending, failed (« Réessayer »), missing (« Récupérer la météo »),
  unavailable (hidden).
- **Analyse card**: a « Météo » tab — the hourly table, its icons static;
  each row highlights the stretch until the next sample on the profile and
  the map. While the tab is active, `Allure::Weather::Markers` places markers
  at the start, then only where the weather changes (another condition, the
  wind turning to another of the eight compass sectors at 1.5 m/s or more, or
  a 2 °C move), at least 8 % of the distance apart and six at most; an
  unchanging weather gets one marker halfway. The profile draws them as rose
  pills with the white animated condition icon (ECharts draws it as one
  composed image symbol, recomposed when the theme changes, static under
  reduced motion; the tooltip names the condition, the hour, the temperature
  and the wind); the map as small rose pills with the white icon, the
  temperature and an arrow pointing where the wind blows, counter-rotated by
  the map's bearing. Owner-only: a reader has the summary, never a positioned
  instant. The splits table gains an effective-wind column.
- **Elevation chart**: « Température » and « Vent effectif » secondary series.
- **Feed**: a shared summary adds its icon and temperature range to the card's
  date line. The owner's timeline cards and table carry nothing yet.
- **Publishing profile form**: the `weather` checkbox with its shared /
  not-shared wording (§19.1 list gains « la météo (résumé) »).
- Units follow `unit_system` (°C/°F, km/h/mph, mm/in); stored values stay SI.
- Every string in `fr.yml` and `en.yml`.

## 8. Programmatic surfaces

- REST: the detailed `Workout` carries `weather` (`WorkoutWeather`: status,
  `WeatherSummary`, `hours` — never a coordinate); a feed publication or
  received note carries `weather` (`WeatherSummary`) when shared. No new
  route. The ETag follows the weather row.
- MCP: `get_workout_context` reuses the detail serializer, so it carries the
  same `weather`.
- No new webhook event.

## 9. Operations

- `/admin/jobs`: audited weather backfill; `/admin/system`: configuration,
  endpoints, last-24-h requests against the budget, failure counts.
- `/metrics`: `allure_weather_requests_total{endpoint,result}`,
  `allure_workout_weathers{status}`; `Metrics::Catalog` mapping and i18n guard.
- Queue: the default queue; `limits_concurrency` paces the provider.
- Federation ring and seeds keep `WEATHER_ENABLED` unset, except the fake
  provider in `fed_test`.

## 10. Tests

- Pure: sampler (hours, rounding, cell dedupe, untimed track), u/v
  interpolation across 350°→10°, WMO mapping, exposure on an out-and-back
  under constant wind (≈ 50 % head / 50 % tail), a loop under crosswind,
  stopped-time exclusion, summary circular mean.
- Client: WebMock with pinned Open-Meteo JSON fixtures, query assertions (no
  coordinate with more than one decimal, ten variables, ≤ 10 locations),
  forecast → archive fallback, 429 with `Retry-After`.
- Jobs: eligibility matrix (manual, credit, positionless, virtual, consent
  off, feature off), budget reschedule, refresh triggers, offline analysis
  convergence, readiness check.
- Requests: consent page, owner-only series endpoint (404 otherwise), REST and
  OpenAPI contract, MCP.
- Privacy negatives: no series in a snapshot, no weather when the profile
  disables it, parser rejection cases.
- Federation: serializer/parser round trip, `fed_test` phase.
- Browser: workout page, Analyse tab, light/dark, both locales, phone width.

## 11. Device temperature

Many devices record the air temperature they measure. It needs no provider and
no consent: it is a recorded channel like heart rate.

- `Allure::Fit::Parser` decodes `record.temperature` (field 13, sint8 °C) and
  `Allure::Gpx::Parser` the Garmin `gpxtpx:atemp` extension; TCX has none.
- `Allure::Gpx::Point` gains `temperature`; the stored point JSON gains the
  `temp` key in whole °C (`WORKOUT.md`), readings outside −60…70 dropped. No
  workout column: the card derives mean/min/max from the stored points on
  read. The analyzer version marker is bumped; `BackfillRebuildJob` fills
  existing workouts from their originals.
- Owner-only display: « Temp. capteur » on the weather card (or a card of its
  own when the workout cannot have weather), and a « Température (capteur) »
  series on the profile (`ChartSeries` `device_temperature`). The copy notes
  that a device in the sun or against the body reads warmer than the air.
- Never published or federated in this contract; REST and MCP expose it to the
  owner like the other recorded channels.

## 12. Deferred

- The map's wind colouring and arrow.
- Timeline and table weather icons.
- The credit-row weather read-through beyond the source publication.

## 13. Out of scope

- Air quality.
- Any provider other than Open-Meteo.
- A height correction of the 10 m wind.
