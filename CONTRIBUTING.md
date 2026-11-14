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

The optional development dataset is built from the FIT conformance corpus:

```sh
script/fetch-fit-corpus
dip rails db:seed
```

It takes about ten minutes and creates the demo accounts described in
[README.md](README.md). `DEMO_SEED_LIMIT=n` imports at most `n` activities per
account.

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
- The design reference and the contracts behind a durable behaviour are
  maintained with the source; a pull request explains the contract it
  implements until the developer documentation is published.

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
