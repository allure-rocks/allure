# Contributing to Allure

Thanks for taking the time to contribute. Allure is a Rails monolith for
importing, analysing and sharing GPS activities over ActivityPub, and it is
developed in the open at <https://github.com/allure-rocks/allure>.

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md). For a
security issue, do not open a public issue: follow [SECURITY.md](SECURITY.md).

## Licence and sign-off

Allure is licensed under the GNU Affero General Public License v3.0 or later.
By contributing you agree that your contribution is licensed under the same
terms. Every commit must carry a Developer Certificate of Origin sign-off:

```sh
git commit -s -m "Describe the change"
```

The `DCO` workflow refuses a pull request whose commits lack a
`Signed-off-by` line. Use your real name and an address you can receive mail
at; a GitHub noreply address is fine.

## Development environment

The host needs only Docker and [dip](https://github.com/bibendi/dip). Ruby,
Node, PostgreSQL and every native extension live inside the development image.

```sh
cp .env.example .env
dip provision     # destructive: resets the local databases
dip up
```

The application is then on <http://localhost:3001>. `dip provision` is
destructive; for an existing checkout use `dip bundle install`,
`dip npm install`, `dip rails db:prepare` and `dip up` instead.

### Demo dataset

The optional development dataset is built from the FIT conformance corpus:

```sh
script/fetch-fit-corpus
dip rails db:seed
```

The seed imports about 125 real activities into ten accounts that each live
somewhere coherent, plus a newcomer and a suspended account, and builds the
social state around them through the ordinary services: equipment, privacy
zones, publishing profiles, publications (immediate, scheduled, through a
custom profile), shared and private segments with their course publications,
routes, follows, participations, comment threads, reactions, an import batch
with a failed entry, an API token, a paused webhook, an invitation and an audit
trail. Re-running the seed writes nothing it already did; the first run takes
about ten minutes, and the route images, segment matching and geocoding then
finish on the workers.

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

Some outings were recorded by three devices at once, so Tom, Joan and Inès hold
their own copy of the same outings: the shared segments rank three athletes,
the linked participations name each other's recordings, and the comment threads
sit on the shared outings.

`DEMO_DATASET=minimal` seeds the two-account set the federation ring uses
(`marie` and `paul`, three activities each, with committed GPX fallbacks when
the corpus is missing); `DEMO_SEED_LIMIT=n` imports at most `n` activities per
account.

### Commands

```sh
dip ls                  # list everything available
dip up                  # db + rails + vite + worker (applies pending migrations)
dip rails c             # console
dip rails db:migrate    # forward/rollback without restarting the stack
dip rspec               # test suite
dip fed_test            # reproducible two-node federation gate
dip fed_restricted_test # followers-only federation gate
dip rubocop -a
dip psql                # psql session (respects RAILS_ENV)
dip npm install
dip sh                  # shell in the app container
dip docs                # operator documentation on http://localhost:5173
```

### Code layout

```
app/federation/       ActivityPub services and jobs
app/frontend/         Vite root — entrypoints, Stimulus controllers, SCSS
app/services/         Persistence transactions and storage orchestration
config/navigation.rb  The single source of truth for the navigation
docs/dev/             Design reference and developer contracts
docs/site/            Operator documentation (docs.allure.rocks)
lib/allure/           Framework-independent domain code, including federation privacy
spec/                 RSpec; federation specs run offline against pinned fixtures
```

## Checks

Run the focused specs while you work, and the complete gate before opening a
pull request:

```sh
dip rspec
dip rubocop
dip brakeman
dip sh -c bin/bundler-audit
dip vite build
dip npm run test:route-renderer
dip npm run test:igpsport
dip npm run test:shared-files
dip npm run test:import-source
dip docs_build
```

The full RSpec suite takes about fifteen minutes. The optional FIT corpus spec
(`spec/lib/allure/fit/corpus_spec.rb`) is skipped unless the corpus is
fetched; run it deliberately for parser or analyzer work.

The database is PostgreSQL 18 with PostGIS 3.6. SQLite is not a supported test
substitute.

## Federation tests

Federation is tested in three tiers.

Tiers 1 and 2 need **no domain and no certificates**: the suite runs entirely
offline against pinned fixtures, and two-Allure rings run over plain HTTP on a
Docker network. `dip fed_test` proves the public exit (delivery, rendering,
media, duplicate handling, tombstones, republishing, isolation, unfollow, actor
deletion and key retirement); `dip fed_restricted_test` proves the
followers-only exit (promoted-only delivery, signed object and media
authorization, and revocation with purge). Tier 3 — real instances behind
stable public HTTPS hostnames — is a manual gate, not part of CI.

## Frontend

There is no JavaScript test suite. The browser is the end-to-end check for
anything under `app/frontend/`: verify the behaviour in the browser and read
the console. Stimulus controllers own their resources and release them in
`disconnect`; Turbo Drive is mandatory, so do not bind behaviour in
`DOMContentLoaded`.

The Playwright MCP server runs at `http://localhost:8932/mcp` and its browser
reaches the application at `http://rails:3001`.

## Translations

French is the default locale; English is the full fallback; German, Spanish and
Dutch are complete. Every user-visible change updates all five files in the
same patch:

```text
config/locales/{fr,en,de,es,nl}.yml
```

The `spec/i18n/locale_completeness_spec.rb` spec fails on a missing key, an
extra key, a changed interpolation variable or a missing help page. Do not
hardcode user-facing English.

## Documentation

- `docs/site/` is the operator documentation published at
  <https://docs.allure.rocks>. A change to an environment variable, to
  `docker-compose.production.yml` or `production.env.example`, to an operator
  rake task or to the deployment updates its pages in the same patch.
- `docs/dev/DESIGN.md` is the design reference and `AGENTS.md` is the
  repository guide. A contract that is not published yet is marked
  `[devdoc:<topic>]` in those files, and a pull request explains the contract
  it implements until the document lands.

## Commits and pull requests

- Keep commits focused and explain the why in the message, not only the what.
- Explain the contract a change implements when one exists.
- Add or update the specs in the same commit as the behaviour.
- A pull request that changes the UI includes a screenshot or a short
  recording.
- Do not commit generated files (`db/schema.rb` is dumped by Rails), secrets,
  local `.env` files, storage blobs or the FIT corpus.

## Reporting a bug or proposing a feature

Use the issue templates. A bug report names the version (the footer shows it),
the surface, the exact steps and what you expected. A feature request explains
the problem before the solution; check the existing issues and the operator
documentation first.
