# Repository Guide

Allure is a self-hostable, federated sport-tracking application: a Rails
monolith for importing, analysing and sharing GPS activities across the
fediverse. Members import the files their watch, bike computer or phone
records, read a detailed analysis of every outing, and publish a sanitized copy
to the audiences they choose. This file documents the repository as it exists
and the constraints future changes must preserve.

## Documentation

`docs/dev/DESIGN.md` is the binding design and UX reference: voice, the
glossary, tokens, sport identity, information architecture, component
vocabulary, states, accessibility, and the mandatory privacy copy. It applies to
all UI work. Read it before writing any view, Stimulus controller, navigation
entry, or user-facing string. Where it conflicts with a data or protocol
contract, the contract wins and `DESIGN.md` is amended.

`docs/dev/CHARTS.md` is the charts contract: the shared ECharts foundation, the
rules every chart follows and the chart-by-chart contracts.

`docs/dev/MAPS.md` is the maps contract: the MapLibre engine, the basemap, the
controls, the track colouring, the hover synchronisation and the smoothing.

`docs/dev/ACCESS.md` is the access contract: every browser surface requires an
account, while the ActivityPub wire contract is unchanged.

`docs/dev/AUTH.md` is the authentication contract: the two sign-in paths, the
second factor, the identity providers, the sessions and the iOS handoff.

`docs/dev/ACCOUNT.md` is the account contract: the export archive, the
seven-day deletion window and the resumable purge.

`docs/dev/API.md` is the API contract: the REST resources, the API tokens, the
webhooks and the OpenAPI document.

`docs/dev/MCP.md` is the MCP contract: the endpoint, the location levels and
the read tools.

`docs/dev/METRICS.md` is the metrics contract: the endpoint, the metric
catalog, the privacy negatives and the reference dashboard.

`docs/dev/ADMIN.md` is the administration contract: the operator console, its
panels, the audit log and the suspension and invitation rules.

`docs/dev/PUBLISHING.md` is the publishing contract: the source workout, the
profile, the immutable publication, the audiences and the federation boundary.
`docs/dev/DELAYED-PUBLISHING.md` is the safety-delay contract, and
`docs/dev/AUTO-PUBLISHING.md` is the automatic-publishing contract.
`docs/dev/REACTIONS.md` is the reactions contract: the four types, the toggle,
the audience rule and the wire. `docs/dev/COMMENTS.md` is the comments
contract: the thread per audience, the one level of replies, the moderation,
the wire and the relay. `docs/dev/SHARED-ACTIVITIES.md` is the
shared-activities contract: the participants, the credit and link kinds, the
credited metric set, the reduced federated invitation and the co-presence
detection.

`docs/dev/PEOPLE.md` is the people contract: the opt-in directory, the name
search, the suggestions and the relationship hub.

`docs/dev/NOTIFICATIONS.md` is the notifications contract: the inbox, its
kinds, the producers, the withdrawal and the surfaces.

`docs/dev/PUSH.md` is the push contract: the relay protocol, the payload, the
instance subscriptions and the companion bridge.

`docs/dev/WORKOUT.md` is the workout contract: the source workout, the
recording segments, the units, the GPX input, the metrics engine, the import
transaction and the route image. `docs/dev/FIT.md` is the FIT import contract,
and `docs/dev/POWER.md` is the power-duration contract.

`docs/dev/SEGMENTS.md` is the segments contract: courses, routes, loops,
efforts, splits, personal bests and leaderboards.
`docs/dev/SEGMENTS-FEDERATION.md` is the course-only federation contract,
`docs/dev/SMART-LAPS.md` the detected-laps contract, and
`docs/dev/BEST-EFFORTS.md` the standard-distance best-efforts contract.

`docs/dev/FEDERATION.md` is the federation contract: permanent identity,
signatures, discovery, inbox and outbox, delivery, remote identity and follows,
remote notes and media, the safety gate and the restricted audience.

`docs/dev/VIRTUAL-PLATFORMS.md` is the virtual-platforms contract: the platform
catalogue, the world maps, virtual sports, venue naming, distance calibration
and teleports.

`docs/dev/NO-GPS.md` is the positionless-recordings contract: the
classification, the device readings, the analysis without geometry, the
persistence, the skipped derivations and the publication refusal.

`docs/dev/ELEVATION.md` is the terrain-elevation contract: the provider, the
two-level opt-in, the sampling and profile, the device totals, the per-workout
source and the course terrain.

`docs/dev/WEATHER.md` is the weather contract: the provider, the hourly series
and the wind exposure, the publication summary and the device temperature.

`docs/dev/DERIVATIONS.md` is the derived-data contract: the derivation map, the
generation markers, the sweeps and the owner-scoped rebuilds.

`docs/dev/HEART-RATE.md` is the heart-rate contract: the profile, the zones,
the histogram, the training load, the zone distribution and the privacy
boundary.

`docs/dev/PHOTOS.md` is the photos contract: the owner's photos, the quota,
the placement along the route, the frozen publication copies and the
programmatic surfaces.

`docs/dev/REMOTE-IMPORTS.md` is the remote-imports contract: the provider
registry, the connection model, the adapter contract, the batch job, the shared
lifecycle and the provider capabilities. The detailed sign-in and operational
notes stay in a local-only companion.

`docs/dev/IMPORT-SOURCES.md` is the import-sources contract: the registry, the
file source, the Strava archive, the iGPSPORT device source, the remote sources
and the manual source.

`docs/dev/MANUAL-ENTRY.md` is the manual-entry contract: the typed workout,
its shape and validation, and what it counts for.

`docs/dev/STRAVA-ARCHIVE.md` is the Strava archive contract: the source, the
reading bounds, the sport mapping, the job and the archive's photos.

`docs/dev/DEMO.md` is the demo contract: the mode switch, the re-dated data,
the shared accounts, the nightly reset and the reset strip.

`docs/dev/FUNDING.md` is the funding contract: the tiers, the paid periods,
the supporter badge and the provider seam.

`docs/dev/BULK-ACTIONS.md` is the bulk-actions contract: the selection, the
quick actions and the reviewable background operations.

The developer contracts are published under `docs/dev/`; each document above is
the current reference for its area. A new contract is written in its own file
before the code that depends on it lands.

`AGENTS.local.md`, when present in the checkout, adds local notes for this
machine. It is ignored by Git and never published; read it after this file.

`docs/site/` is the operator documentation published at
<https://docs.allure.rocks> (VitePress, English only, its own `package.json`,
excluded from the production image by `.dockerignore`; see
`docs/site/README.md`). It is for people who install and run an instance, not
for members or contributors. Any change to an environment variable, to
`docker-compose.production.yml` or `production.env.example`, to an operator rake
task, or to the deployment updates its pages in the same patch:
`spec/docs/environment_reference_spec.rb` fails when a variable read by the
application, the production Compose file or the example is missing from
`docs/site/configuration/environment.md` (or documented but read by nothing),
and `spec/docs/rake_tasks_spec.rb` when a page names a task that does not
exist. The site documents the latest release only (`config/version.rb`); the
`docs` job of `.github/workflows/release.yml` publishes it on release tags.

Members' help lives in the application at `/help` (`HelpController::TOPICS`,
`DESIGN.md` §20.20): a handful of concept pages — publishing, privacy zones,
sharing beyond the instance, segments and leaderboards, training load — whose
bodies are locale-specific partials
(`app/views/help/topics/_<topic>.{fr,en,de,es,nl}.html.erb`), reached from the
account menu and from `HelpHelper#help_link` beside the hints they extend. They
quote §19 texts through the screens' own locale keys; a change to one of those
behaviours updates its page in every language in the same patch.

## Domain map

- **Workout core.** `Allure::Gpx::Parser`, `Allure::Fit::Parser` and
  `Allure::Tcx::Parser` produce the shared immutable `Allure::Gpx::*` values;
  `Allure::Gpx::Analyzer` computes metrics offline, without Active Record.
  Analysis versions are generation markers on `workouts.analysis_version`; a new
  version must be additive and backfillable. `Workouts::Importer` validates and
  uploads the original, persists the workout and its ordered `TrackSegment`
  rows in one transaction, and compensates a failed storage upload. Persisted
  metrics use SI units, public workout ids are ShortUUID-encoded UUIDs, and
  recording segments stay separate across pauses.
  [docs/dev/WORKOUT.md](docs/dev/WORKOUT.md)
- **Publication and privacy.** An imported workout is private until its owner
  publishes it. `PublishingProfile` is the single sharing policy;
  `WorkoutPublication` is an immutable sanitized representation with the
  lifecycle `unpublished -> published -> deleted`, and republishing creates a
  new identity. Privacy zones filter interior points before the snapshot is
  made; `mask_start` and `mask_finish` govern the endpoints and fail closed. A
  workout carries at most one live publication per audience, and
  `Workouts::PublicationResolver` serves each reader the narrowest one they may
  read. [docs/dev/PUBLISHING.md](docs/dev/PUBLISHING.md)
- **Federation.** `Allure::Federation::Config` is the only source of permanent
  instance identity: base URL, scheme, host, port, actor and collection URIs.
  Every federated id derives from it. WebFinger, HTTP Signatures, SSRF-safe
  transport, signed inbox admission, durable follow and delivery state,
  tombstones (`410 Gone`), blocks and inbound rate limiting live under
  `app/federation/`; the two-node ring is `docker-compose.fed.yml`.
  [docs/dev/FEDERATION.md](docs/dev/FEDERATION.md)
- **Segments and best efforts.** `Segment` is a reusable course and is never
  owned by a workout; `SegmentEffort` links a workout to it. `TrackSegment` is a
  recording segment — the two are different things and the codebase keeps them
  apart by name. Boards are derived on read per viewer, personal bests are per
  `(segment, athlete, sport)`, and `best_efforts`/`effort_records` hold the
  standard-distance efforts.
  [docs/dev/SEGMENTS.md](docs/dev/SEGMENTS.md)
  [docs/dev/BEST-EFFORTS.md](docs/dev/BEST-EFFORTS.md)
- **Social.** Comments (one level of replies, the origin hosts the thread),
  reactions (one active per actor and target), shared activities (credit and
  link rows), `/people` discovery, and in-app notifications. Each has one write
  seam and its own notification switch.
  [docs/dev/COMMENTS.md](docs/dev/COMMENTS.md)
  [docs/dev/REACTIONS.md](docs/dev/REACTIONS.md)
  [docs/dev/SHARED-ACTIVITIES.md](docs/dev/SHARED-ACTIVITIES.md)
  [docs/dev/PEOPLE.md](docs/dev/PEOPLE.md)
  [docs/dev/NOTIFICATIONS.md](docs/dev/NOTIFICATIONS.md)
- **Remote imports.** `ImportConnection` keeps one encrypted credential set per
  account and provider; `Workouts::RemoteImportBatchJob` lists a range once and
  imports each entry through `Workouts::Importer`. Garmin Connect, EXR, Withings
  and Zwift are operator-enabled adapters under `ImportConnections::Providers`
  and each appears only when its variable is set; the Strava archive source is
  always available. No health data is imported.
  [docs/dev/REMOTE-IMPORTS.md](docs/dev/REMOTE-IMPORTS.md)
  [docs/dev/STRAVA-ARCHIVE.md](docs/dev/STRAVA-ARCHIVE.md)
- **API, webhooks, MCP.** A versioned REST API under `/api/rest/v1` (not
  `/api/v1`, which names the ActivityPub objects), scoped `ApiToken`s, RFC 9457
  problems, encrypted keyset cursors, rate limits, ETag and `Idempotency-Key`.
  `WebhookEndpoint`/`WebhookEvent`/`WebhookDelivery` sign Standard Webhooks
  deliveries. `POST /mcp` serves read-only tools through `AllureMcp::Server`;
  coordinates leave only at the token's `mcp_geometry` level. The OpenAPI 3.1
  document is hand-written at `docs/openapi/v1.yaml`, validated by the suite and
  served at `/developers/api`. [docs/dev/API.md](docs/dev/API.md)
  [docs/dev/MCP.md](docs/dev/MCP.md)
- **Administration and operations.** `/admin` sits behind the single
  env-configured operator (`Admin::BaseController` answers 404 to everyone
  else); `AdminEvent` and `Admin::Audit` record every operator mutation
  append-only. `/metrics` is the Prometheus exporter behind `METRICS_TOKEN`.
  [docs/dev/ADMIN.md](docs/dev/ADMIN.md)
  [docs/dev/METRICS.md](docs/dev/METRICS.md)
- **Accounts and authentication.** Session lifetimes, a second factor (TOTP,
  passkey, recovery code), identity providers, re-authentication, the iOS
  sign-in handoff, the self-service export, and the seven-day deletion window
  with a resumable purge. [docs/dev/AUTH.md](docs/dev/AUTH.md)
  [docs/dev/ACCOUNT.md](docs/dev/ACCOUNT.md)
- **Enrichment.** Terrain elevation (an OpenTopoData-compatible server),
  historical weather (Open-Meteo), heart-rate zones and training load, photos
  with stripped derivatives and placement, and geocoded places. Each is opt-in,
  each derived dataset carries its own version or status marker, and none of it
  enters a publication snapshot unless its profile setting says so.
  [docs/dev/ELEVATION.md](docs/dev/ELEVATION.md)
  [docs/dev/WEATHER.md](docs/dev/WEATHER.md)
  [docs/dev/HEART-RATE.md](docs/dev/HEART-RATE.md)
  [docs/dev/PHOTOS.md](docs/dev/PHOTOS.md)
- **Virtual platforms and positionless recordings.**
  `Allure::Virtual::Platforms` names a platform from the FIT `file_id`; a
  virtual world's map image is drawn instead of the basemap and its attribution
  ships with it. A positionless recording is measured from the device's own
  distance and speed, stored with empty geometry, and refused publication with
  `no_geometry`.
  [docs/dev/VIRTUAL-PLATFORMS.md](docs/dev/VIRTUAL-PLATFORMS.md)
  [docs/dev/NO-GPS.md](docs/dev/NO-GPS.md)
- **Demo and seeds.** `db/seeds.rb` seeds the reference catalogs in every
  environment and the demo dataset in development only; `Allure::Demo` turns an
  instance into a throwaway demo; `DemoSeed::Runner` drives the manifests
  through the ordinary services. [docs/dev/DEMO.md](docs/dev/DEMO.md)

## Locked Stack

| Area | Implementation |
|---|---|
| Runtime | Ruby 4.0.x, Rails 8.1.4.1 |
| Database | PostgreSQL 18 with PostGIS 3.6 |
| Persistence | Active Record using `activerecord-postgis-adapter` |
| Jobs | Solid Queue |
| Metrics | Yabeda with the Prometheus text exporter at `/metrics` |
| Cache | Solid Cache gem and cache database declared; explicitly inactive |
| Cable | Action Cable; async/test adapters locally and Solid Cable in production |
| Storage | Active Storage tables installed; local/test disk currently configured |
| Server frontend | ERB and Rails helpers |
| Browser frontend | Turbo Drive, Stimulus, Vite |
| iOS companion | Swift, UIKit/SwiftUI, Hotwire Native; iOS 17+, separate repository |
| Theme | Tabler 1.6 on Bootstrap 5.3 |
| Maps/charts | MapLibre GL JS 6, Apache ECharts 6 (SVG renderer) |
| Pagination | Pagy 43 |
| Tests | RSpec, FactoryBot, Shoulda Matchers, WebMock, VCR |
| Development | Docker Compose controlled through dip |

The locked architecture has no Redis; production Cable uses its dedicated Solid
Cable database. There is no SPA framework, importmap, Propshaft, Sprockets,
jQuery, ViewComponent, Devise, or authorization gem. Do not add one incidentally
when a small Rails/Hotwire implementation fits the established architecture.

Commercial theme material must never enter this repository. Tabler is the
redistributable MIT UI foundation.

## Development Environment

### Host requirements

For Rails development the host needs only Docker and dip. Ruby, Node, Bundler,
npm, PostgreSQL clients, GEOS, PROJ, and native gems belong in the development
image. Do not use a host Ruby or host Node installation for repository work.

The Hotwire Native companion is a separate repository, normally checked out
beside this one. Its local, Git-ignored `backend/` symlink points here for code
inspection and `dip` commands. Read that repository's own guide, design
reference and README for native work. It owns its Swift code, native
translations, assets, Xcode project, version and macOS CI. This repository owns
Rails and web UI changes, with its own commits and release gate. Native builds
need macOS and full Xcode; the Foundation core also builds with Swift
command-line tools. Rails-side bridge components live under
`app/frontend/controllers/bridge/`; a surface that must not appear in the
companion is hidden from `hotwire_native_app?`.

First setup:

```sh
cp .env.example .env
dip provision
dip up
```

`dip provision` is destructive: it starts with
`docker compose down --volumes --remove-orphans`. It deletes PostgreSQL and other
Compose volumes. Never use it merely to install a new gem or refresh containers
unless resetting all local databases is intended.

For an existing checkout, use focused commands such as:

```sh
dip bundle install
dip npm install
dip rails db:prepare
dip prepare_test_db
dip up
```

Pending migrations need no manual step: the `rails` service runs `db:prepare`
before Puma, so `dip up` or a container restart applies them, and the production
web container does the same on boot. The production web container also runs
`db:seed` after migrating, because the reference catalogs (sports, equipment
types) are seed data, not schema: a catalog addition must reach an existing
database on deploy. `dip rails db:migrate` remains for forward/rollback without
restarting the stack.

### Compose services

`docker-compose.yml` defines:

| Service | Purpose |
|---|---|
| `db` | Multi-arch `imresamu/postgis:18-3.6`, exposed to the host on port 5443 by default |
| `rails` | Rails server on host port 3001 |
| `vite` | Vite development server on host port 3037 |
| `worker` | Solid Queue worker for the default, internal recurring (`solid_queue_recurring`), federation, federation-media, remote-imports, webhooks and photos queues |
| `route-image-worker` | Low-concurrency Solid Queue worker with Chromium for `route_images` |
| `playwright` | Playwright MCP server on host port 8932 |

The application source is bind-mounted at `/app`. Bundler and shell history use
named volumes. `node_modules` intentionally remains in the bind mount so host
editor tooling and reference inspection can read installed frontend packages.

PostgreSQL 18 stores its data under a major-version directory, so the Compose
volume correctly mounts `/var/lib/postgresql`, not the pre-18
`/var/lib/postgresql/data` path.

The database container initializes the neutral `postgres` database. Rails
creates application databases from clean `template1`; this prevents extra
extensions enabled by the image entrypoint from polluting `db/schema.rb`.

### dip commands

Prefer these interactions over raw Docker Compose commands:

```sh
dip up                              # start services; applies pending migrations
dip sh                              # shell in the Rails image, no dependencies
dip rails c                         # Rails console
dip rails db:migrate                # development migration
dip bundle install                  # Bundler in the image
dip npm install                     # npm in the image
dip rspec                           # complete RSpec suite in RAILS_ENV=test
dip rspec spec/path_spec.rb         # focused spec file
dip rspec spec/path_spec.rb:42      # focused example
dip prepare_test_db                 # create/load test databases
dip rubocop                         # Ruby style
dip brakeman                        # static security scan
dip psql                            # development primary database
dip psql_test                       # test primary database
dip fed_a                           # Rails console on federation ring node A
dip fed_b                           # Rails console on federation ring node B
dip fed_prepare_a                   # create/seed ring node A databases
dip fed_prepare_b                   # create/seed ring node B databases
dip fed_test                        # full federation ring scenario
dip fed_restricted_test             # gated restricted-federation ring scenario
dip docs_install                    # install the documentation site's packages
dip docs                            # serve docs/site on http://localhost:5173
dip docs_build                      # build docs/site; fails on a dead link
```

Run `bin/bundler-audit` inside the container when the host does not have the
locked Ruby environment.

`package.json` has focused Node tests for static-map input validation,
simplification, the iGPSPORT protocol, shared files and the import-source
contract, but no general frontend test, lint, formatter, typecheck, or build
script. Do not claim broader frontend checks ran unless the application was
verified through Vite/browser loading.

### Playwright

The MCP server is at `http://localhost:8932/mcp`, but its browser runs inside
Compose. Navigate that browser to `http://rails:3001`, not
`http://localhost:3001`. Development host authorization explicitly permits
`rails:3001`.

There is no general JavaScript test suite; the focused Node tests cover the
static route renderer, the iGPSPORT protocol, shared files and the import-source
contract. The browser remains the only end-to-end check for anything in
`app/frontend/`. Verify frontend work in the browser and read the console; do
not infer from a green RSpec run.

Known environment noise to separate from real failures:

- the isolated browser cannot reach Vite's host-side HMR websocket and reports
  that development-only connection failure even when everything works;
- the basemap styles may log sprite and legacy-filter warnings that are not
  failures.

### Development tools (`devtools/`)

`devtools/` holds development-only tooling, loaded by a single guard in
`config/application.rb`:

```ruby
require_relative "../devtools/lib/dev_tools" if Rails.env.local?
```

It must be required there — before `Rails.application.initialize!` — so the
engine's routes, views and locales register with the application. Nothing under
the namespace exists in production: the require never runs, the directory is
listed in `.dockerignore` and the production `Dockerfile` copies an explicit
list of folders that excludes it, so a `COPY devtools` fails at build time
instead of shipping the tool. Shared code keeps only the hooks: a guarded
`lookup_context.exists?` render of `layouts/dev_tools_bar` in the application
layout, the same for `layouts/dev_tools_menu` in the account menu, and the
`DevTools::Impersonation` concern included into `ApplicationController` through
the engine's `config.to_prepare`.

The first tool is **impersonation**, the answer to a demo seed with a dozen
personas: the operator (and it is always the operator — `/devtools/impersonation`
answers 404 to anyone else, and the entry is rendered for nobody else) opens a
session as any active account from the account menu's « Agir en tant que… ».
Starting one asks for the same second-factor step-up as `/admin`; the run itself
does not, so a page that needs a recent proof of identity behaves exactly as it
does for the target. The operator's own session is parked in the Rails session
(`DevTools::Impersonation::PARKED_SESSION_KEY`, dropped by any later sign-in or
sign-out like the flow keys around it) and the cookie moves to a fresh
session for the target, created through the application's own
`start_new_session_for`. A warning bar above the topbar follows every page while
it lasts, « Revenir à @x » restores the operator without a password or a second
factor, and signing out during an impersonation returns the browser to the
operator instead of ending the browser session (the shared controller then
lands on the sign-in page, where any navigation continues as the operator).
Everything done while impersonating is done as the target — publishing,
comments, reactions, federation — which is the point in development.
`spec/requests/devtools_impersonation_spec.rb` locks the 404s, the step-up, the
round trip and the sign-out path.

### Federation ring

`docker-compose.fed.yml` runs two complete Allure instances that federate with
each other over plain HTTP on the Compose network. Every service sits behind the
`federation` profile, so `dip up` never starts any of it.

| Node | URL | Database | Worker |
|---|---|---|---|
| A | `http://allure-a.test:3002` | `db-a`, host port 5444 | `worker-a` |
| B | `http://allure-b.test:3003` | `db-b`, host port 5445 | `worker-b` |

One host prerequisite, once:

```text
127.0.0.1 allure-a.test allure-b.test
```

Run the reproducible gate with:

```sh
dip fed_test
```

The separate restricted gate exports `FEDERATION_RESTRICTED_ENABLED=true` so
both nodes and workers boot with it:

```sh
dip fed_restricted_test
```

The gates need no `/etc/hosts` entry because every request stays on the Compose
network. They stop the six ring services, drop and recreate only the A/B
databases, start the two nodes and workers without their ordinary dependencies,
and exercise discovery, signed `Follow`/`Accept`, sanitized public `Create`,
`Delete`, idempotent redelivery, media rendering, withdrawal and actor
deletion; the restricted run additionally promotes A on B, publishes a
followers-only route, and proves signed object/media authorization for the
entitled follower, refusal for an unsigned or non-follower request, and
unfollow revocation with media purge. Polling is bounded to 60 seconds per
assertion by default; override it with `FEDERATION_RING_TIMEOUT`. A failure
prints the last 200 log lines from both nodes and workers. The gate always
stops the ring but preserves its final databases for diagnosis. It never stops
or resets the ordinary development stack, and explicitly disables the optional
GitLab integration and geocoding (`GEOCODING_BASE_URL` is emptied over the
developer's `.env`): a rate-limited provider once kept every worker thread
retrying the seeded rides' toponymy while federation jobs waited past the
polling bound. For the same reason the ring nodes seed the `minimal` demo
dataset (`DEMO_DATASET=minimal` in `docker-compose.fed.yml`), never the full
one.

For interactive use, the host aliases above are required:

```sh
dip compose --profile federation up -d
dip fed_prepare_a
dip fed_prepare_b
dip compose stop allure-a allure-b worker-a worker-b db-a db-b
```

Stop the ring with `stop`, not `down`: `docker compose down` is project-wide and
would take the ordinary development stack and the network with it.

The `fed_prepare_*` interactions deliberately wrap `dip compose ... run -T`
instead of declaring `compose.profiles` on a service interaction. Dip 8.3 turns
every profiled interaction into `docker compose up`, removes its command and run
options, and would attach to the Rails server instead of preparing the database.
The `fed_a`/`fed_b` console interactions use `docker compose exec` and keep their
TTY; only non-interactive preparation and test commands pass `-T`.

Each node listens on exactly the port it publishes, so a single URL resolves
identically from the host browser and from inside the Compose network. That
equality is the whole design: the port is part of the permanent actor identity,
and a node whose advertised port differs from its listening port cannot receive
deliveries. Do not "tidy" the ports to the main development port.

Other properties that are load-bearing rather than incidental:

- `FEDERATION_PROTOCOL=http` and `ALLOW_PRIVATE_IPS=true` are required together;
  the SSRF guard permits an `http://` target only when both hold;
- `.test` is already in `ALLOWED_HOSTS_IN_DEVELOPMENT`, so no host-authorization
  entry is needed, unlike the `rails:3001` alias;
- both nodes share the `.:/app` bind mount, so each passes its own Puma pidfile;
  the default `tmp/pids/server.pid` would stop the second node from booting;
- each node mounts its own named volume on `/app/storage`, so sanitized
  publication media never mix;
- both nodes proxy to the single existing `vite` service, which is why
  `VITE_ALLOWED_HOSTS` must list the two aliases;
- starting the ring also starts `vite` and the primary `db` through the
  dependency chain;
- `dip provision` also destroys the ring volumes, because the file is merged
  permanently.

Two limits are deliberate:

- a newly resolved remote actor has `capability_profile: unknown`, so only
  **public** publications fan out; a followers-only publication is correctly
  skipped until that peer is explicitly promoted, which the restricted ring
  covers;
- a received course becomes a local segment only through an explicit copy
  action; no remote object is imported automatically and the copy never syncs
  back to the origin.

Follows are also available from `/people` and each profile header. From the
console:

```ruby
Federation::Follow.new(user: User.first, target: "@marie@allure-b.test:3003").call!
Federation::FollowDecision.new(following: Following.pending.first, decision: "accept").call!
```

`Federation::TargetResolver` routes every handle form to WebFinger:
`@marie@allure-b.test:3003`, `marie@allure-b.test:3003` and
`acct:marie@allure-b.test:3003` all resolve remotely, so the `acct` and
`handle` an actor row stores can be passed back verbatim as a follow or
unfollow target. A bare username, or a handle whose domain is this instance,
resolves locally; anything else — an absolute URI, or a value carrying a
scheme — is treated as a literal actor URI.

A phase that signs in through `ActionDispatch::Integration::Session` must reset
`ActiveSupport::ExecutionContext.nestable` to false (`integration_session`
does). Loading the integration session marks contexts nestable, as a test case
would. The runner never pushed a context, so the request's executor pops it to
nil, and every later query fails with `undefined method '[]' for nil` in
`QueryLogs`.

## Database Architecture

Every environment declares the PostGIS Active Record adapter and four logical
databases:

| Role | Development database | Purpose |
|---|---|---|
| primary | `allure_development` | application rows and PostGIS data |
| cache | `allure_development_cache` | reserved for Solid Cache |
| queue | `allure_development_queue` | Solid Queue |
| cable | `allure_development_cable` | reserved for Solid Cable |

Test and production declare the same role layout with their environment
prefixes. Solid Queue is connected to its queue role in development and
production. The cache role remains an architectural placeholder: Solid Cache is
not selected and no workout behavior depends on it. The cable role contains the
generated Solid Cable schema and production connects to it explicitly.

`config/database.yml` uses:

- `adapter: postgis`;
- `postgis_extension: postgis`;
- `schema_search_path: public`;
- role-specific migration paths for cache, queue, and cable.

The primary schema contains users, sessions, sports, workouts, ordered workout
segments, Active Storage, and PostGIS. The spatial spec proves Point and
LineString geography round trips, GEOS/PROJ support, geodesic length, spatial
predicates, and GeoJSON conversion.

Database-backed specs require the real PostgreSQL/PostGIS service. SQLite is not
a supported test substitute. If the test database is absent, run
`dip prepare_test_db` before RSpec.

The test database carries the seeded reference catalogs: CI starts from an empty
PostgreSQL service, and `db:prepare` seeds a freshly created database, so the 38
sports and the equipment types are already there when RSpec starts. A spec that
needs a catalog sport must resolve it with the `catalog_sport` helper
(`find_or_create_by!`) rather than `create(:sport, slug: …)` — the factory raises
on the seeded unique slug and label. Seed a local test database the same way to
reproduce CI:

```sh
RAILS_ENV=test docker compose run -T --rm \
  -e DATABASE_URL=postgis://allure:allure@db:5432/allure_test \
  rails bin/rails db:seed
```

Never hand-edit:

- `db/schema.rb`;
- `db/queue_schema.rb`;
- generated cache/cable schemas;
- migration output.

Create a migration, run it through Rails in the container, and let Rails dump
the schema. Model validations should mirror important database constraints but
do not replace them, especially for public identifiers, visibility values,
ordering, and non-negative metrics.

## Application Architecture

### Code boundaries

| Path | Responsibility |
|---|---|
| `app/models/` | Active Record entities, associations, persisted invariants |
| `app/controllers/` | HTTP authentication/authorization, orchestration, responses |
| `app/views/` | Server-rendered ERB and plain partials |
| `app/helpers/` | presentation and navigation helpers |
| `app/jobs/` | Active Job entry points; durable execution uses Solid Queue |
| `app/services/` | persistence transactions and orchestration seams |
| `app/frontend/` | Vite source: entrypoints, Stimulus controllers, SCSS |
| `app/federation/` | ActivityPub identity, transport, inbox, outbox, parsers |
| `app/mcp/` | the read-only MCP tools |
| `lib/allure/` | framework-independent domain code and configuration objects |
| `config/navigation.rb` | the only application navigation tree |
| `spec/` | RSpec suite and pinned external fixtures |

Keep calculation-heavy, framework-independent behavior under `lib/allure/` when
it can operate on values without Active Record. Keep persistence transactions
and Active Storage orchestration in small services under `app/services/`, as
`Workouts::Importer` demonstrates. Do not create abstract service bases or
repositories without demonstrated reuse.

### Rails frameworks

The application loads Active Model, Active Job, Active Record, Active Storage,
Action Controller, Action Mailer, Action View, and Action Cable. Action Mailbox,
Action Text, and Rails' Minitest railtie are disabled.

`lib/` is autoloaded and eager-loaded through `config.autoload_lib`, excluding
`lib/assets`, `lib/tasks` and `lib/middleware`. Constants in `lib/allure/` must
match Zeitwerk file names.

System tests are disabled in generator configuration. Browser verification is
performed through Playwright rather than generated Rails system tests.

### Existing models and authentication

`User` owns:

- username, normalized email, password digest;
- locale (one of `fr`, `en`, `de`, `es` and `nl`);
- theme (`light` or `dark`);
- unit system (`metric` or `imperial`);
- display identity;
- federation URI helpers derived from configuration.

Usernames are restricted by both model validation and a database check. Reserved
names protect application and ActivityPub routes: `User::RESERVED_USERNAMES`
covers protocol endpoints, infrastructure, brand, audience and application
names — a guard spec keeps the last group in step with `config/routes.rb` — and
the configured `INSTANCE_NAME`, normalized to username space, is refused to
self-registration. Do not weaken or bypass these checks when adding profile or
federation routes.

`Session` belongs to `User`. Rails 8 generator-style authentication stores a
signed permanent `session_id` cookie and records user agent/IP on session rows.
`Current.session` provides request-local state and `current_user` delegates
through it.

`ApplicationController` includes `Authentication`, requires authentication by
default, permits only modern browsers, and resolves locale in this order:

1. valid `?locale=` parameter (on a signed-out request it is also remembered
   in the `allure_locale` cookie, which the sign-in pages' language switcher
   sets — `DESIGN.md` §10.24);
2. signed-in user's locale;
3. for a signed-out visitor, the `allure_locale` cookie, then the best match
   of the browser's `Accept-Language` (`Allure::AcceptLanguage`, primary
   subtag only), then English (`VISITOR_FALLBACK_LOCALE`).

French stays `I18n.default_locale` for everything outside a request (mailers
and jobs use the account's locale). Signed-out HTML answers `Vary:
Accept-Language, Cookie`, and the registration form gives the new account the
language it was read in. Rack::Test sends no `Accept-Language`, so
`spec/support/accept_language.rb` makes request specs browse as a French
browser unless an example sends its own header.

Public controllers/actions must opt out explicitly with
`allow_unauthenticated_access`. Mutating resources must scope records through the
current owner rather than loading a global row and checking later.

### Errors

`config.exceptions_app = routes` sends application exceptions through
`ErrorsController`, the error layout, helpers, and i18n rather than static public
HTML files. Routes for 404, 410, 422, and 500 are directly previewable and tested.

`Allure::Federation::TombstonedError` maps to 410. Preserve that distinction:
deleted federated actors must answer Gone, not Not Found.

### Views and layout

The main Tabler layout is `app/views/layouts/application.html.erb`:

- `<html>` receives the locale, server-selected `data-bs-theme`, and
  `data-bs-layout="fluid"`;
- federation discovery can be injected through `content_for :federation_links`;
- Vite supplies the single application entrypoint;
- the horizontal topbar precedes a `.page-wrapper`;
- views may provide `content_for :page_header`;
- body content and footer use `.container-xl`.

New normal application pages should follow the existing conventions:

- set `content_for :title`;
- use `content_for :page_header` with Tabler page title markup;
- use `.row.row-deck.row-cards`, `.card`, and `.empty` patterns;
- use plain ERB partials and helpers;
- avoid inline styles and untranslated user-facing literals;
- never add an inline `<script>`, an event-handler attribute or `eval`: the
  Content-Security-Policy (`config/initializers/content_security_policy.rb`,
  origins from `Allure::ContentSecurityPolicy`) allows only this origin's
  scripts, and a standalone page that must run one uses
  `javascript_tag nonce: true`. A new third-party origin the browser reaches
  belongs in that module, not in a looser directive.

`DESIGN.md` governs anything beyond those mechanics: which component to use, its
states, its copy, its accessibility, and the mandatory privacy wording. Do not
invent a new pattern without adding it there first.

Every form that saves something is guarded against silent loss by the shared
`unsaved-changes` controller (`shared/_unsaved_changes`, `DESIGN.md` §14.3): a
dialog asks before a navigation, a reload or another form's save would drop its
entries. Nothing follows the fields while typing and no surface is pinned to the
viewport. A form whose fields hold a transient choice opts out with
`data-unsaved-changes="off"`; a validation summary carries
`data-unsaved-changes="forced"`.

Authentication/password views are still mostly Rails-generator markup, a known
gap that the product-UI work closes. Do not use them as the visual standard for
new pages. `DESIGN.md` §25 lists that gap alongside the other known deviations.
Privacy zones are placed with the map picker and its Nominatim place search
(`DESIGN.md` §14.4, `GET /settings/privacy-zones/search`), and listed in the
same table as the publishing profiles.

## Navigation

`config/navigation.rb` is the single source of truth. Do not hand-code a second
primary navigation tree in views.

The navigation DSL supports:

- key: translation suffix under `navigation.*`;
- icon: Tabler icon name without `ti-`;
- path: route-helper symbol or dynamic proc;
- policy: optional helper predicate such as `signed_in?`;
- children: recursively rendered entries.

`config/initializers/navigation.rb` reloads the tree in a `to_prepare` block, so
navigation changes hot-reload in development. Active state is computed on the
server by `NavigationHelper`.

An unresolved route helper intentionally causes that leaf item to be omitted;
parents with valid visible children remain usable as dropdowns. The tree already
contains future routes. Do not add a duplicate item when a route starts
existing.

Navigation labels must exist in every locale file. Never put translated text in
`config/navigation.rb` itself.

## Frontend Architecture

### Vite entrypoint

`app/frontend/entrypoints/application.js`:

1. imports the SCSS entrypoint;
2. enables Turbo Rails;
3. starts Stimulus;
4. exposes Tabler/Bootstrap JavaScript as `window.bootstrap` for `data-bs-*`
   components;
5. eagerly auto-registers every `*_controller.js` under
   `app/frontend/controllers/`.

New Stimulus controllers require no manual registration. Name them according to
`stimulus-vite-helpers` conventions.

Vite's `~` alias resolves to `app/frontend/`. Frontend source does not live under
`app/javascript/`.

### Turbo rules

Turbo Drive is mandatory. Do not:

- bind application behavior in `DOMContentLoaded` handlers;
- retain third-party instances on cached DOM nodes;
- rely on full page reloads to reset state.

Put DOM behavior in Stimulus `connect`/`disconnect`. A controller that owns a
map, chart, observer, timer, event listener, or fetch must release it on
disconnect. Abort in-flight requests when they can outlive the element.

The map controller demonstrates the required pattern: it aborts its in-flight
style and track fetches, removes its markers, and calls `map.remove()` on
disconnect. It also guards against being disconnected while its dynamic
`import()` or its style-ready callback is still pending, which is the failure
mode a lazily loaded library introduces.

MapLibre is imported dynamically inside `connect`. It is around 250 kB gzipped
and every controller here is registered eagerly, so a static import would charge
that to the timeline, the dashboard and every other page with no map.

MapLibre 6 builds its worker URL from a runtime template that no bundler can
resolve statically, so `setWorkerUrl` is called with Vite's `?worker&url` query.
Plain `?url` emits the worker without the sibling module it imports and fails
only in production. Do not simplify that import.

### Coordinates

The repository-wide geometry convention is:

```text
[longitude, latitude]
```

That is GeoJSON/PostGIS order, and it is also MapLibre's own order, so nothing
in the map path converts axes. Do not reintroduce a `[latitude, longitude]`
representation. Multi-segment tracks must remain separate so maps do not draw
false connecting lines across recording gaps.

### Styles and assets

The SCSS entrypoint lives at `app/frontend/styles/application.scss`. It loads
brand variables before Tabler, then Tabler theme styles, the Tabler icon font,
MapLibre CSS, and local component styles.

`_brand.scss` holds only the semantic surface tokens plus the font/icon-font
settings; sport identity has no per-sport palette — every sport tile carries
the same brand-primary tint. The per-sport icon map lives in
`Allure::SportPalette` and is globally distinct. Font files under
`public/fonts/tabler/` are generated by `bin/sync-icon-fonts` during npm
installation.

Do not hand-edit:

- `public/vite-*`;
- `public/fonts/tabler/`;
- `tmp/cache/vite/`.

Every chart controller loads ECharts on demand through `lib/charts/echarts.js`,
mounts it with `lib/charts/lifecycle.js` (SVG renderer, resize observer) and
calls its `release()` (`dispose()`) during disconnect; no chart reads a library
internal. Both map and chart controllers abort pending authorized-data fetches
when Turbo disconnects them.

## Internationalization

- French is the default locale.
- English is the full fallback.
- Available locales are exactly `fr`, `en`, `de`, `es` and `nl`
  (`config/initializers/locale.rb` and `User::LOCALES`, kept equal by a spec).
  German, Spanish and Dutch use the informal address and the `DESIGN.md` §4.1
  glossary; the language picker names each language in itself.
- Missing translations raise in development and test.
- Production falls back to English rather than raising.

Every user-visible change must update every locale file —
`config/locales/{fr,en,de,es,nl}.yml`, and `devtools/config/locales/` for the
development tools — in the same patch. This includes model names/attributes,
validation messages where customized, buttons, flash messages, empty states,
chart/map errors, units, and accessibility text.
`spec/i18n/locale_completeness_spec.rb` fails when a locale lacks a key, carries
one the reference locales (French and English) do not, changes an
interpolation variable or a list length, or lacks a help page. French and
English remain the reference texts for `DESIGN.md` §19; the German, Spanish and
Dutch privacy copy translates them faithfully.

Use translation keys in views and controllers. Existing hardcoded English flash
messages in generated session/password code are known debt, not a precedent.

## Federation Identity Boundary

`Allure::Federation::Config` is the only source for permanent instance identity:

- base URL;
- scheme, host, and port;
- actor, key, inbox, outbox, followers, and following URIs;
- profile URL, handle, and WebFinger account;
- local-URI checks;
- private-IP escape hatch for the local test ring.

All federated IDs must derive from this object. Never hardcode a hostname,
reconstruct an actor URI from a handle, drop a non-default port, or infer HTTPS.
Scheme, host, and port together form permanent actor identity.

`FEDERATION_BASE_URL` defaults to `http://allure.test:3001` in development.
`ALLOW_PRIVATE_IPS=true` is a local-ring escape hatch in Compose; production must
default to false. Do not use the escape hatch to weaken ordinary outbound-fetch
validation.

`FEDERATION_PROTOCOL` selects the configured `http` or `https` protocol and must
match the scheme in `FEDERATION_BASE_URL`. Plain HTTP is only for the local test
ring with `ALLOW_PRIVATE_IPS=true`; production must use HTTPS.

`INSTANCE_OPERATOR_USERNAME` names the single account allowed to open `/admin`.
Development Compose defaults it to the seeded `marie` account so the console is
reachable locally; production has no default, and an unset value means no
account is an operator.

`METRICS_TOKEN` is the bearer token for `/metrics`. When it is unset the endpoint
answers 404 and computes nothing; in development and production Compose it is
forwarded from the environment and documented in the env examples. It is read at
call time and is never rendered anywhere.

`INSTANCE_NAME`, `INSTANCE_DESCRIPTION`, `INSTANCE_HOST_NAME`, and
`INSTANCE_HOST_URL` are public presentation metadata read by
`Allure::Instance`: the footer host line, NodeInfo `metadata`, and the PWA
description. They never feed actor URIs, keys, or signed objects, every value
stays hidden when unset, and an invalid host URL is ignored.

## Workout and Publication Boundary

The workout core locks decisions that are easy to accidentally invalidate:

- persisted metric values use SI units;
- public workout IDs are ShortUUID-encoded UUIDs, not bigint IDs;
- all 38 sports are slug-keyed seeded reference data;
- GPX algorithms are framework-independent under `lib/allure/gpx/`;
- segments are ordered explicitly and stay separate;
- publication state is explicit and sanitized representations are immutable;
- original GPX, track JSON, chart JSON, and route images each enforce their
  specific owner/publication boundary;
- unauthorized and unpublished representations return 404;
- owner route PNGs render through MapLibre on a dedicated Chromium worker with
  Ruby fallbacks (light and dark variants together, one generation marker),
  publication PNGs render asynchronously on the same worker with raster and
  tile-less fallbacks, and their Create intent waits for the images;
- privacy-zone filtering shipped before any federation; active zones always
  filter interior points, and the selected publishing profile's `mask_start` and
  `mask_finish` settings independently control whether the departure and
  arrival are exempt from zone filtering (disabled) or required to be covered
  and removed (enabled). A segment that never leaves a zone keeps no endpoint
  exemption, so the route fails closed instead of exposing it.

The user-facing sharing model keeps federation terminology out of ordinary
workout interaction:

- An imported workout is `unpublished` until the owner explicitly publishes it.
- `PublishingProfile` is the single user-facing sharing policy for local
  non-owner views and ActivityPub delivery; there is no separate local versus
  federated visibility choice.
- `WorkoutPublication` is an immutable sanitized representation. Its lifecycle
  is `unpublished -> published -> deleted`; republishing creates a new
  publication identity.
- Federation is a distribution channel for an existing publication. A public
  publication is not broadcast to every instance.
- A publication retains an immutable local `actor_id`; an active publication
  retains its source workout, while a deleted publication may retain its
  identity and actor after source deletion nullifies `workout_id`.

Do not silently change units, point JSON keys, ShortUUID alphabet, publication
lifecycle, or GPX metric algorithms. These are protocol/persistence contracts;
update the matching [docs/dev/WORKOUT.md](docs/dev/WORKOUT.md) or
[docs/dev/PUBLISHING.md](docs/dev/PUBLISHING.md) document and
the tests if a demonstrated need changes one.

### Terminology

Two different things are called a "segment", and the codebase keeps them apart
by name:

- **`TrackSegment` / `Workout#track_segments`** — a *recording* segment: one
  contiguous GPX `<trkseg>` between pauses. It was named `WorkoutSegment` until
  `RenameWorkoutSegmentsToTrackSegments`.
- **`Segment`** — the reusable, leaderboarded portion of a course. It is never
  owned by a workout; a workout reaches it through `segment_efforts`.

`Workout#segments` does not exist and must not be reintroduced. Inside the
`Allure::Gpx` namespace, "segment" means one recording segment, historically
the GPX `<trkseg>` and now also the equivalent FIT pause boundary. The
`Allure::Gpx::{Track, Segment, Point, ActivitySignal}` values are the shared
multi-format track contract, so `Allure::Gpx::Segment`, `Track#segments`,
`Analyzer::SegmentMetrics`, and the `segments:` keyword arguments of
`ChartSeries` and `RouteImageRenderer` keep their names. Read the segments
documentation before naming anything in this area.

## Testing

### RSpec structure

- `spec/rails_helper.rb` loads all files under `spec/support/`, maintains the
  test schema, uses transactional fixtures, infers spec types, and includes
  FactoryBot syntax.
- Shoulda Matchers is configured for RSpec and Rails.
- Factories cover users, sports, workouts, track segments, reusable segments and
  efforts, publishing profiles, privacy zones, publications, and local/remote
  actors.
- Database coverage includes a real PostGIS integration spec.
- Importer service coverage proves complete multi-segment persistence for GPX
  and FIT, rollback and blob compensation for segment/attachment/storage
  failures, and enqueue timing after commit.
- Request coverage includes dashboard/errors plus workout authentication,
  visibility/privacy, upload validation, CRUD, timeline, responsive form
  regressions, and authorized GPX download behavior.
- Chart-series coverage proves cumulative multi-segment distance/time, null
  elevation handling, deterministic 1,000-point bounding, and required extrema.
- Track/chart request coverage proves exact payloads, content types, cache
  policy, ShortUUID handling, owner-only geometry, public-analysis access, and
  absence of coordinate/private-field leaks.
- Federation coverage proves discovery, sanitized resources, tombstones, signed
  inbox admission, duplicate suppression, follow/reaction/comment state
  transitions, outbox fan-out, delivery leases, retries, shared inbox grouping,
  and course publication/receipt/copy.
- FIT coverage includes deterministic synthetic decoder cases, batch/archive
  cases, and an optional local conformance corpus of real activity files. The
  corpus is never fetched by CI or committed to the repository.

Run focused specs during development and `dip rspec` before completion. If a
change requires a migration and RSpec reports an absent test database, run
`dip prepare_test_db`; if it reports pending migrations, run the appropriate
test database preparation rather than editing schema files.

### Corpus and performance runs

`spec/lib/allure/fit/corpus_spec.rb` holds one example per real activity file in
the optional local corpus (`references_apps/fit-test-files`, 4 000-plus files).
It parses and analyses every track, so when the corpus is present it dominates
the suite — roughly eight minutes against five for everything else — and it
skips itself when `script/fetch-fit-corpus` has not been run.

Exclude it during development for fast feedback, and run it deliberately before
shipping parser or analyzer work:

```sh
dip rspec --exclude-pattern "**/corpus_spec.rb"
dip rspec spec/lib/allure/fit/corpus_spec.rb
```

Time the analyzer on a large real file from `dip rails runner` with
`Process.clock_gettime(Process::CLOCK_MONOTONIC)`; the `benchmark` standard
library is not a default gem on Ruby 4 and `require "benchmark"` fails. A
48 000-point activity analyses in about one second, and the engine must stay
linear: distance windows are capped in samples for exactly that reason, and new
per-point passes must use sliding ranges rather than rescanning every interval.

### Network isolation

RSpec blocks every real network connection, including localhost, through
WebMock. Tests must:

- stub HTTP explicitly;
- use a pinned VCR cassette;
- avoid requiring browser asset servers in ordinary request specs;
- keep deterministic workout/image processing offline.

Federation cassette recording is deliberate and run inside `dip sh`:

```sh
VCR_RECORD=all bundle exec rspec spec/federation/...
```

Do not casually re-record external fixtures. Review payload changes, remove
sensitive headers/data, and keep cassettes pinned.

### CI reality

`bin/ci` prepares the test database and runs RSpec, RuboCop, bundler-audit, and
Brakeman. `.github/workflows/ci.yml` runs those checks against PostgreSQL
18/PostGIS 3.6 on every pull request and on `main`, and also performs an
explicit Vite build and the focused static-route renderer, iGPSPORT protocol,
shared-files and import-source tests with Node 24. Its `docs` job builds the
operator documentation on every pull request and on `main`, and the `docs` job
of `.github/workflows/release.yml` publishes it to GitHub Pages on release tags.
GitHub is the source host; `.github/workflows/release.yml` publishes the
application and route-image worker images to Docker Hub and creates the GitHub
release from `CHANGELOG.md`.

Configured checks are:

```sh
dip rspec
dip rubocop
dip brakeman
bin/bundler-audit
dip vite build
dip npm run test:route-renderer
dip npm run test:igpsport
dip npm run test:shared-files
dip npm run test:import-source
dip docs_build
```

Do not state a check passed unless it was actually run in the supported
container environment.

## Seeds

`db/seeds.rb` idempotently creates the 38-sport and equipment-type reference
catalogs in every environment, and in development only loads
`db/seeds/development.rb`, the demo dataset. That dataset is development-only
twice over: the require is guarded by `Rails.env.development?`, and
`.dockerignore` keeps `db/seeds/development.rb` and `db/seeds/demo/` out of the
production image, so a `COPY` of either fails the build rather than shipping a
loader whose corpus and fixtures are absent — `spec/config/dockerfile_spec.rb`
locks both halves. `DemoSeed::Runner` (`db/seeds/demo/seeder.rb`) drives a
manifest through the ordinary services — `Workouts::Importer`,
`Workouts::ImportBatchJob`, `Workouts::ManualEntry`, `Segments::Creator` and
`Segments::Publisher`, `Federation::Follow`/`FollowDecision`,
`Workouts::Publisher`, `Participations::Propose`/`Decide`, `Comments::Post`,
`Reactions::Toggle`, `Segments::LocalCopier`, `ApiToken`, `WebhookEndpoint`,
`RegistrationInvitation`, `Admin::Audit` — so the demo state is exactly what
members could have produced. Every step finds before it creates, a failing entry
is reported and never stops the run, and a re-run writes nothing it already did.
Two manifests exist under `db/seeds/demo/manifests/`:

- `full` (the default): ten personas built from the optional FIT corpus
  (`script/fetch-fit-corpus`), each with a coherent home area and repeating its
  own roads, about 145 activities across 17 sports, plus the newcomer `nina`
  (no second factor yet) and the suspended `promo_bot`. Some outings were
  recorded by several devices at once, so several personas each own their copy
  of the same ride, run or hike: shared segments rank several athletes, linked
  participations name each other's recordings, and comment threads sit on the
  shared outings. Segments are anchored by coordinates on their source workout
  (snapped to the nearest recorded points, within one recording segment) and
  were chosen from an overlap analysis of the corpus; keep that property when
  adding one. The demo instance and the development seed both re-date the whole
  dataset from `DemoSeed::Manifests::DATE_ANCHORS`: one anchor per family — the
  newest file recording date and the newest typed manual date — so it ends
  yesterday on a fresh database, while a re-seeded one keeps the shift its
  recordings were first imported with (`DEMO_SEED_SHIFT=0` keeps the files' own
  dates; the federation ring pins it). `spec/seeds/demo_manifest_spec.rb`
  refuses a newer recording without its anchor moving, so adding an activity
  updates the anchor in the same patch. Publications are dated a little after
  their workout rather than at the seed run, and a delayed one whose delay has
  not yet run out from that moment stays waiting — the manifest's delays sit on
  recent activities for that reason. Every seeded profile starts with
  `mask_start`/`mask_finish` off, because a masked endpoint must be covered by a
  zone.
- `minimal`: the historical two accounts (`marie`, `paul`) with three
  activities each and committed GPX fallbacks. `docker-compose.fed.yml` pins
  `DEMO_DATASET=minimal` on both ring nodes so `dip fed_test` keeps its timing,
  and `full` falls back to it when the corpus is missing.

Every seeded password account signs in with the development password documented
in `CONTRIBUTING.md`, with the shared authenticator secret it names there
(`ROTP::TOTP.new(secret).now` from `dip rails c` gives the current code).
Reviewing the dataset from the inside does not need either: the operator
(`marie`) impersonates any seeded persona from the account menu's « Agir en tant
que… » (see "Development tools" above). `DEMO_SEED_LIMIT=n` imports at most `n`
activities per account while working on the seed. The first full run takes about
ten minutes, and the route images, segment matching and geocoding then finish on
the workers (with `GEOCODING_BASE_URL` set, the toponymy of ~125 activities
queues against that provider at its throttled rate).
`spec/seeds/demo_manifest_spec.rb` checks every manifest reference (and the
corpus paths when the corpus is fetched) and `spec/seeds/demo_seed_spec.rb` runs
the loader twice on a fixtures-only manifest that exercises every step.
Production and preproduction remain reference-only; create their accounts
explicitly with `bin/rails users:create`, or issue a single-use, email-bound
`bin/rails users:invite` link when registration must stay closed.

Specs should create rows through factories except when explicitly testing seed
behavior.

## Generated and Sensitive Files

Do not modify generated artifacts manually or include local runtime state:

- `db/schema.rb`, `db/queue_schema.rb`, and other dumped schemas;
- `public/vite-*`;
- `public/fonts/tabler/`;
- `tmp/cache/vite/` and other `tmp/` runtime output;
- `storage/` blobs;
- `.env` and credentials.

Use `.env.example` for documented environment keys. Never commit API tokens,
private federation keys, session cookies, GPX files containing personal routes,
or cassette headers containing signatures.

## Change Discipline

- Prefer the smallest correct change that preserves the architecture above.
- Verify current code before following a future layout.
- Keep migrations, model constraints, factories, specs, and every locale in the
  same feature slice.
- Keep controllers thin and calculations outside Active Record models when they
  can be pure values.
- Do not add compatibility paths for behavior that has never shipped.
- Preserve Turbo lifecycle cleanup for every third-party browser library.
- Preserve GeoJSON axis order and federation identity derivation.
- When a decision changes a durable contract, update the matching developer
  documentation in the same patch, or add its own document.
