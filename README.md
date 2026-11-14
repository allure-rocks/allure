# Allure

[![CI](https://github.com/allure-rocks/allure/actions/workflows/ci.yml/badge.svg)](https://github.com/allure-rocks/allure/actions/workflows/ci.yml)
[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)
[![Docker Hub](https://img.shields.io/docker/pulls/allurerocks/allure)](https://hub.docker.com/r/allurerocks/allure)

A federated sport-tracking application. Import your GPS activities, analyse them,
and publish them over **ActivityPub**. Allure-to-Allure federation is complete:
public and followers-only publications deliver between instances, received
workouts render with their media, and the reproducible two-node rings prove the
public and restricted exits. Interoperability with external
[Wanderer](https://wanderer.to) and Mastodon peers is the post-M5 backlog.

- **Public demo:** <https://demo.allure.rocks> — the credentials are on the
  sign-in page. The instance is reset every night; never import personal data.
- **Documentation:** <https://docs.allure.rocks>
- **Docker images:** `allurerocks/allure` and `allurerocks/allure-route-image`
  on Docker Hub.

Its workout analysis follows the model of
[FitTrackee](https://codeberg.org/FitTrackee/FitTrackee), and its federation
follows the model of [FitPub](https://codeberg.org/fitpub/fitpub); the Wanderer
trail and route-planning interop is post-M5.

See the [architecture guide](https://docs.allure.rocks/guide/architecture) for
the shape of the application.

## Stack

| | |
|---|---|
| Ruby / Rails | 4.0 / 8.1 |
| Database | PostgreSQL 18 + PostGIS 3.6 |
| Jobs, cache, cable | Solid Queue / Solid Cache / Solid Cable (no Redis) |
| Metrics | [Yabeda](https://github.com/yabeda-rb/yabeda) Prometheus exporter at `/metrics` |
| Frontend | Hotwire (Turbo + Stimulus), Vite, [Tabler](https://tabler.io) 1.6 on Bootstrap 5.3 |
| Maps / charts | [MapLibre GL JS](https://maplibre.org) 6 on [OpenFreeMap](https://openfreemap.org) vector tiles, [Apache ECharts](https://echarts.apache.org) 6 |
| Dev environment | Docker + [dip](https://github.com/bibendi/dip) |

## Getting started

Requires Docker and [dip](https://github.com/bibendi/dip) (`gem install dip`).
Ruby, Node and every native extension live inside the image — nothing is
installed on the host.

```sh
cp .env.example .env
dip provision
dip up
```

The app is then on <http://localhost:3001>. `dip up` applies any pending
migrations before the server starts, so an existing checkout only needs a
restart after pulling migration changes. Load the reference catalogs and the
development demo dataset with `dip rails db:seed`. Production creates its
first account explicitly with `dip rails users:create`.

### Development demo dataset

Run `script/fetch-fit-corpus` once, then `dip rails db:seed`. The seed imports
about 125 real activities from the FIT conformance corpus into ten accounts
that each live somewhere coherent, plus a newcomer and a suspended account,
and builds the social state around them through the ordinary services:
equipment, privacy zones, publishing profiles, publications (immediate,
scheduled, through a custom profile), shared and private segments with their
course publications, routes, follows, participations, comment threads,
reactions, an import batch with a failed entry, an API token, a paused
webhook, an invitation and an audit trail. Re-running the seed writes nothing
it already did; the first `dip rails db:seed` takes about ten minutes and the
route images, segment matching and geocoding then finish on the workers.

| Account | Locale | Brings |
|---|---|---|
| `marie` (operator) | fr | road rides (Alpe d'Huez, Grand Cucheron, Uriage), a Chamonix trail, a two-day Sancy hike, an e-bike holiday, cross-country skiing |
| `paul` | en, imperial | bike commutes both ways, long rides, Zwift |
| `sophie` | fr | one runner from 2011 to 2019, a ski day in Gérardmer |
| `tom` | en | runs and rides at home, mountain bike at the Posbank, the Mallorca camps; the API token and the webhook |
| `eva` | en | Tom's running and riding partner, a pool swim, indoor rowing |
| `joan` | en | the Mallorca rides, trails, hikes and open-water swims |
| `ines` | fr | the third recording of the Mallorca outings, solo runs |
| `kasia` | en | a dense running year, three half marathons, walks, a Swedish ski trip; automatic publishing |
| `owen` | en, imperial | windsurfing, paddle boarding, the South West Coast Path |
| `lucas` | en | daily runs and trails from the door; the import batch |
| `nina` | fr | invited newcomer without a second factor yet, a pending follow request, a Dex identity |
| `promo_bot` | en | suspended by the operator |

Every account signs in with `allure-dev-password` and the shared authenticator
secret `ALLUREDEVTOTPSECRETDEMOACCOUNTS2` (`ROTP::TOTP.new(secret).now` from
`dip rails c` gives the current code; `nina` has no second factor yet). Tom's
API token `allure_pat_dev-demo-token-0000000000000000000000000000` carries
every scope with filtered MCP geometry, for REST and MCP experiments.

Some outings were recorded by three devices at once, so Tom, Joan and Inès
hold their own copy of the same outings: the shared segments rank three
athletes, the linked participations name each other's recordings, and the
comment threads sit on the shared outings.

`DEMO_DATASET=minimal` seeds the two-account set the federation ring uses
(`marie` and `paul`, three activities each, with committed GPX fallbacks when
the corpus is missing); `DEMO_SEED_LIMIT=n` imports at most `n` activities
per account.

## Production installation

The operator documentation — requirements, installation with
`docker-compose.production.yml`, secrets, reverse proxy, first account and
every environment variable — is published at <https://docs.allure.rocks>. Its
source is [`docs/site/`](docs/site/README.md).

Published images are `allurerocks/allure:<tag>` and
`allurerocks/allure-route-image:<tag>` on Docker Hub; `latest` follows the
newest release. Set both in `.env.production` and run `docker compose pull`
before `up`. The release workflow builds them from the same tag as the GitHub
release.

## Commands

```sh
dip ls                  # list everything available
dip up                  # db + rails + vite + worker (applies pending migrations)
dip rails c             # console
dip rails db:migrate    # forward/rollback without restarting the stack
dip rspec               # test suite
dip fed_test            # reproducible two-node federation gate
dip rubocop -a
dip psql                # psql session (respects RAILS_ENV)
dip npm install
dip sh                  # shell in the app container
dip docs                # operator documentation on http://localhost:5173
```

## iOS companion

The Hotwire Native iOS companion is maintained in the separate `allure-ios`
repository, normally checked out alongside this one at `../allure-ios`. Its
local `backend/` symlink points to this Rails checkout for development.

Open `../allure-ios/Allure.xcodeproj` with Xcode 16+ and run on an iOS 17+
simulator. Start this backend with `dip up`, then use `http://localhost:3001`
in the companion's Debug configuration. The companion's `README.md` documents
device setup, native tests and its independent macOS CI/release gate.

The app reuses the existing Rails UI and cookie login, with native server
selection and Back navigation. Native push delivery is the next slice; the
existing in-app notification inbox is available through the reused UI.

## GitLab feedback

The optional feedback widget lets authenticated users capture and annotate the
current page before creating an issue in a GitLab project. Enable it in `.env`
and restart the application:

```sh
GITLAB_ENABLED=true
GITLAB_API_URL=https://gitlab.com/api/v4
GITLAB_PROJECT_ID=group/allure
GITLAB_TOKEN=your-project-token
GITLAB_LABELS=feedback,allure
GITLAB_CONFIDENTIAL=false
```

`GITLAB_PROJECT_ID` accepts a numeric project ID or a namespace path. The token
is used only by Rails and is never exposed to the browser. When the integration
is disabled or incomplete, the widget is hidden and the submission endpoint is
closed.

## Monitoring

`/metrics` exposes Prometheus metrics behind `METRICS_TOKEN`, and
[`docs/grafana/allure.json`](docs/grafana/allure.json) is a ready Grafana
dashboard. Setup, the metric catalog and its caveats are on
<https://docs.allure.rocks/operations/monitoring>.

## Layout

```
app/federation/       M2 boundary for ActivityPub services and jobs (implemented)
app/frontend/         Vite root — entrypoints, Stimulus controllers, SCSS
config/navigation.rb  The single source of truth for the sidebar
docs/site/            Operator documentation (docs.allure.rocks)
lib/allure/            Framework-independent domain code, including federation privacy
spec/                  RSpec; federation specs run offline against pinned fixtures
```

The local publishing core and Allure-to-Allure federation are implemented:
signed inbox, outbox, delivery, remote publication rendering, entitlement-scoped
media, the operator safety gate, and the separately gated followers audience all
exist. External Wanderer and Mastodon interoperability is post-M5, as is the
controlled HTTPS gate.

## Testing federation

Federation is tested in three tiers.

Tiers 1 and 2 need **no domain and no certificates**: the suite runs entirely
offline against pinned fixtures, and two-Allure rings run over plain HTTP on a
Docker network. `dip fed_test` proves the public exit (delivery, rendering,
media, duplicate handling, tombstones, republishing, isolation, unfollow, actor
deletion, and key retirement); `dip fed_restricted_test` proves the
followers-only exit (promoted-only delivery, signed object/media authorization,
and revocation with purge). Tier 3 — real instances behind stable public HTTPS
hostnames — is a manual gate, not part of CI.

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) for the
development environment, the checks and the DCO sign-off, and
[SECURITY.md](SECURITY.md) to report a vulnerability privately. The design and
the contracts behind a durable behaviour are explained in the pull request
until the developer documentation is published.

## Credits

Allure is an independent project, not a fork of any of these. Their behaviour
informed the design; their code is not included.

- [FitTrackee](https://codeberg.org/FitTrackee/FitTrackee) (AGPL-3.0) — the
  workout-tracking model: file import, metrics, visibility and the shape of the
  activity pages.
- [FitPub](https://codeberg.org/fitpub/fitpub) (AGPL-3.0-or-later) — the
  ActivityPub model: publication delivery, idempotency, tombstones and privacy
  zones.
- [Endurain](https://github.com/endurain-project/endurain) (AGPL-3.0) — the
  activity-media model (a path and a type, thumbnails, positions on the map,
  the gallery and lightbox) and the reference for the remote import model
  (Garmin Connect).
- [Wanderer](https://wanderer.to) (AGPL-3.0) — the trail and route-planning
  vocabulary Allure targets for interoperability (post-M5).

The optional FIT conformance corpus used by the development seed and the parser
specs is [ThomasKuehne/FIT-test-files](https://github.com/ThomasKuehne/FIT-test-files);
it is fetched on demand, never committed, and remains under its own terms.

Third-party components that ship with Allure — Font Awesome Free, Meteocons,
Tabler, MapLibre, Apache ECharts, the Garmin Connect port, the Zwift world data
and the FIT profile tables — are credited in [`NOTICE`](NOTICE).

## Licence

AGPL-3.0-or-later (see [`LICENSE`](LICENSE)); the documentation is under the
same licence. Third-party components and their attributions are listed in
[`NOTICE`](NOTICE). The UI is built on Tabler (MIT); no commercially licensed
theme assets are included, which is what keeps this repository distributable.
