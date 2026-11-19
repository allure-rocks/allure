# Demo contract

A **demo instance** is a throwaway public Allure whose database is recreated
from the development seed every night and whose shared member account's
credentials are published on the sign-in page. It exists so a visitor can walk
in and touch everything — import, publish, comment — and so the next morning
is pristine again. `DESIGN.md` governs the visuals; where the two conflict on
a data or protocol contract, this document wins.

## 1. The mode switch

`Allure::Demo` (`lib/allure/demo.rb`) reads `DEMO_INSTANCE` (default off).
The switch changes three things and nothing else:

1. **No second factor is owed** (§3, `AUTH.md`'s demo exception).
2. **The accounts named by `DEMO_ACCOUNTS`** are shared playgrounds (§3).
3. **No session IP is ever persisted** (§4).

Everything else — publication contracts, federation identity, metrics, the
REST API — behaves exactly as on an ordinary instance. A demo is not a
reduced build: it is the same application with a different life expectancy.

The demo deployment is a Compose file and a host runbook. The production image
never changes: the demo image extends the same commit's production image with
the seed files, the GPX fixtures and only the FIT corpus files the manifests
name (`db/seeds/demo/corpus_files.txt`, kept equal to the manifests by
`spec/seeds/demo_manifest_spec.rb`). It is built on the demo host from a
release tag and never published by CI: the corpus is not redistributed.
`spec/config/dockerfile_spec.rb` keeps all of it out of the production image.

## 2. Re-dated data

The development dataset's recordings must look current, so the seed re-dates
them:

- `Allure::Gpx::Track#shifted(seconds)` moves every point time and every
  recorded lap start by one offset, leaving positions, durations and sensor
  readings untouched. The stored original keeps its own dates.
- `Workouts::Importer` takes an optional `time_shift:` and persists it as
  `workouts.time_shift_seconds`; `Workouts::OriginalTrack` re-applies the
  stored offset on every re-analysis (rebuild, sport change, terrain), so no
  path ever falls back to the file's own recording day.
- `DemoSeed::Manifests::DATE_ANCHORS` (in `db/seeds/demo/manifests/full.rb`)
  carries one anchor per family — the newest recording date of the files and
  of the typed manual entries; `MINIMAL_DATE_ANCHORS` does the same for the
  minimal dataset, its committed GPX fixtures included, and
  `DemoSeed::Datasets` pairs each `DEMO_DATASET` with its anchors.
  `spec/seeds/demo_manifest_spec.rb` keeps the anchors honest: a newer
  recording must move its anchor in the same patch.
- `DemoSeed::Dating` computes `shift = end date − anchor` per family. The end
  date is yesterday on a database without the dataset; a database that
  already holds it reads the end date back from its seeded recordings'
  `time_shift_seconds`, so a re-run (a mid-day restart, a development
  `db:seed` weeks later) dates a new entry beside the old ones. `Demo::Reset`
  seeds through `DemoSeed::Runner` with it and `enrol_second_factor: false`.
- **The development seed is re-dated the same way** (`db/seeds/development.rb`),
  so a local database looks like the demo. `DEMO_SEED_SHIFT=0` keeps the
  files' own dates; the federation ring pins it (`docker-compose.fed.yml`).
  A database seeded before re-dating keeps its dates (the stored shift is 0)
  until it is reset.
- **Publications are dated from their workout**, not from the seed run: each
  goes out a deterministic while after its workout's finish (mostly within
  ninety minutes, sometimes hours or the next morning, a second audience a few
  minutes after the first), never later than the present, so the feed mixes
  the accounts in a plausible order. A delayed request ends its delay from
  that moment: a delay that already ran out is an active publication dated at
  its end; one still running stays scheduled until then, which is why the
  manifest's few delays sit on its newest activities. The seeder rewrites
  `published_at`/`scheduled_for` through the relation, its own exception to a
  publication's immutability.

**Yesterday, never today.** The nightly reset runs long before some
recordings' original time of day, and the workout model refuses a start in
the future (`started_at` may not be more than five minutes ahead), so the
dataset must end yesterday.

Known limitation: an original downloaded from the demo (and an account export
re-imported elsewhere) shows the file's real dates; the shift is a fact about
the demo's workouts, not about the files.

## 3. Shared accounts and the second-factor exception

The accounts named by `DEMO_ACCOUNTS` have their credentials published on the
sign-in page, with `DEMO_PASSWORD` displayed beside them. **The operator is
never published** — running `/admin` on a public credential was judged too
dangerous — and no background persona is reachable either: the demo's seed
assigns the shared password to the published accounts only, a fresh random one
to every other account on every pass, and `DEMO_OPERATOR_PASSWORD` to the
configured operator. The operator's password is mandatory in the demo
deployment, stable across the nightly reset, never displayed on the sign-in
page, and refused when it is shorter than `User::MINIMUM_PASSWORD_LENGTH`,
equal to `DEMO_PASSWORD`, or the repository's public development constant.
`Allure::Demo.validate!` refuses an operator in the shared list (usernames are
normalized) or a configured operator without a usable password;
`config/initializers/demo.rb` checks it at boot, before a server or worker
starts, and the same check runs before the seed assigns passwords or the
sign-in page renders credentials. No visitor may lock the next one out: in
demo mode,

- `Auth::SecondFactorPolicy` answers `:satisfied` for everyone, the operator
  included — nothing is owed, nothing is enforced, and the grace banner never
  renders. An account that *is* enrolled still answers its factor at sign-in;
  only the obligation is lifted. `counts` (the metrics exporter) follows.
- The operator console's step-up (`require_recent_second_factor`,
  `AUTH.md`) accepts a recent password proof instead: an operator without a
  factor can still open `/admin` after re-authenticating — for the operator's
  own browser, since their credentials are not public.
- Every mutation of the published account's credential state is refused
  **server-side** by `refuse_demo_account_lockout` (concern
  `DemoAccounts`): the password change, TOTP enrolment and removal, passkey
  registration and removal, recovery-code regeneration, identity unlinking,
  and the account deletion request. The flash says why
  (`demo.account_locked`). Everything else stays writable — that is the
  point of the demo, and the nightly reset heals the rest. The username is
  already immutable at the database level for everyone.

The seed's social steps would leave a wall of unread red on the bell: after
seeding, `Demo::Reset` marks every notification read except the newest few
(`UNREAD_NOTIFICATIONS`) of each published account, so a visitor finds a
quiet inbox with a badge worth clicking.

The sign-in page's block names the account, the shared password and the
privacy sentence (`demo.credentials.*`, `DESIGN.md` §20.21). Registration
stays closed on a demo (`ALLOW_REGISTRATION=false`): the block is the only
door.

**Account addresses.** A manifest names its accounts; their addresses are
built at seed time by `DemoSeed::Emails` — the local part is the username, the
domain the instance's own host (`Allure::Federation::Config#host`). A
development checkout therefore seeds `marie@allure.test`, the public demo
`marie@demo.allure.rocks`, and the federation ring `marie@allure-a.test`; no
address looks like a real person's mail and no manifest hardcodes a host.
`DEMO_EMAIL_DOMAIN` pins another domain when the host is not the one the
addresses should carry. The seeder finds an account by username, its immutable
identity, then reassigns the address: a database seeded under another domain is
renamed in place, never duplicated.

The seed also turns on the optional surfaces the demo is meant to show
(`WEATHER.md`, `DESIGN.md` §19.38): historical weather for the accounts a
visitor browses (`weather_enrichment_enabled` in the manifest,
`WEATHER_ENABLED=true` in the demo env) and the shared profile totals and
records.

## 4. Visitor privacy

Every surface that shows a session's IP would show it to strangers on a
shared account — the security page and the account export. In demo mode
`start_new_session_for` therefore persists `ip_address` as nil, once, at the
source; no screen or export needs a special case. The user agent stays
(useful to the sessions table).

The credentials block carries the sentence: data shared between visitors,
wiped every night, **import nothing personal**.

## 5. The nightly reset

The reset is a recreation, not a wipe: there is no truncate code anywhere in
the application.

- The host runs `bin/demo-nightly-reset` from cron every minute. The wrapper
  resolves the checkout and env file to absolute paths, sources the env file,
  and acts at or after `DEMO_RESET_AT` (in the file's `TZ`). A host-side
  `flock` in `tmp/demo-reset/lock` prevents overlapping runs; the persistent
  `tmp/demo-reset/last-success` date prevents a second successful reset that
  day. Missed schedules and failures are retried by the next cron invocation.
  Every Compose call explicitly pins `--project-name allure-demo`, the
  project directory, env file and Compose file, so an inherited
  `COMPOSE_PROJECT_NAME` cannot redirect a destructive reset. Configuration
  is validated before `down -v`; `up -d --pull never --wait --wait-timeout 1800`
  must see the server's `/up` healthcheck succeed before the date is recorded.
  The database, storage and queue volumes all start empty. The reset never
  pulls: a new version reaches the demo only when the operator pulls it.
- The rails container boots through `bin/demo-boot`: `db:prepare` →
  `db:seed` (the reference catalogs) → `bin/rails demo:reset` → the server.
  The first visitor never sees a half-built instance.
- `demo:reset` (task in `lib/tasks/demo.rake`, service `Demo::Reset`) seeds
  only. It refuses to run without `DEMO_INSTANCE`, requires the seed files
  only the demo image carries, is idempotent (find-before-create), and reports
  failures without stopping the individual steps; any failed step makes the
  task fail and prevents the server from starting. The demo keeps
  `FEDERATION_ENABLED` off: `Federation::Follow` permits local targets without
  the wire protocol, but refuses remote targets before any resolution or
  discovery request.
- **The schedule exists in exactly one place**: the demo env file's
  `DEMO_RESET_AT` + `TZ`, read by both the wrapper and the application's
  warning strip (`Allure::Demo.reset_at`). Two values documented as identical
  would not be a single source.
- **Session ids**: a fresh database hands out `sessions` ids from 1 again,
  and yesterday's signed cookie (a signed *integer*) would resume tomorrow's
  stranger's session. `Demo::Reset` starts the sequence at a random offset —
  only while the table is empty, so a mid-day re-run never collides with
  live sessions.

Effects to accept: everyone is signed out each night, everything visitors
added disappears, the enrichments (route images, toponymy, matching, weather)
settle on the workers for a while after the reset, and the instance is
unreachable during the rebuild (the reverse proxy serves the maintenance
page; the application cannot). Mid-day container restarts are harmless:
`demo:reset` re-runs idempotently and keeps the existing dates.

## 6. The reset strip and the T−5 warning

- **Site-wide strip** (`layouts/_demo_strip`, every layout including the auth
  and admin ones): « Instance de démonstration — tout est réinitialisé
  chaque nuit à HH:MM », the hour from `Allure::Demo.reset_at`.
- **The warning must appear without a reload** (a visitor's page may have
  been open for hours): the strip carries `data-demo-reset-at-value`
  (an absolute instant) and `data-demo-reset-window-value`
  (`Allure::Demo::RESET_WARNING_WINDOW`, five minutes); the Stimulus
  controller `demo_reset_controller.js` ticks every ten seconds and reveals
  the warning line by itself. The browser is the only test for this — there
  is no JavaScript suite.
- The pattern is `DESIGN.md` §20.21; `spec/requests/demo_mode_spec.rb` locks
  the markup and the gating.

## 7. Environment

| Variable | Meaning | Default |
|---|---|---|
| `DEMO_INSTANCE` | the master switch | off |
| `DEMO_ACCOUNTS` | the published playground usernames, comma-separated | empty |
| `DEMO_PASSWORD` | the shared password displayed on the sign-in page and assigned to the published accounts | unset falls back to the development constant |
| `DEMO_OPERATOR_PASSWORD` | the operator's stable password, assigned by the seed and never published; required with `INSTANCE_OPERATOR_USERNAME` | none |
| `DEMO_RESET_AT` | the nightly reset, `HH:MM` | `03:00` |
| `TZ` | the zone both the wrapper and the strip read | `UTC` |
| `DEMO_DATASET` | manifest for `demo:reset` | `full` |
| `WEATHER_ENABLED` | historical weather for the manifest's opted-in accounts | off |

`demo.env` is excluded from both Git and the Docker build context. Keep it
readable only by the operator (`chmod 600`); `demo.env.example` alone is
versioned. `DEMO_ACCOUNTS` must never contain `INSTANCE_OPERATOR_USERNAME`;
the operator's password must differ from `DEMO_PASSWORD` and from the
development constant.

All of them are documented on the operator site
(`spec/docs/environment_reference_spec.rb` enforces it). `AUTH_2FA_GRACE_DAYS`
and `INSTANCE_OPERATOR_USERNAME` behave exactly as on any instance: on a
demo the policy short-circuits before the grace period is ever consulted.

## 8. Testing

- `spec/lib/allure/demo_spec.rb` — the switch, the account list, the
  operator exclusion, the operator password rules and the reset-at resolution
  across the warning window.
- `spec/config/demo_deployment_spec.rb` — the boot-time operator and password
  refusals, the host wrapper's preflight, secret-file exclusions, server
  healthcheck and the real host wrapper in a disposable checkout with fake
  Docker and clock executables: absolute paths, fixed project, once-per-day
  success, concurrency, retries and failures.
- `spec/federation/follow_spec.rb` — local relationships still work with
  federation off; remote targets are refused before discovery.
- `spec/lib/allure/gpx/track_spec.rb` — `#shifted`.
- `spec/services/workouts/importer_spec.rb`, `reanalyzer_spec.rb` — the
  shift at import and, the key one, **kept through a re-analysis**.
- `spec/jobs/workouts/import_batch_job_spec.rb` — the shift through a batch.
- `spec/seeds/demo_manifest_spec.rb` — the anchors stay the newest dates.
- `spec/seeds/demo_seed_spec.rb` — the Runner's shifts and the factorless
  seeding.
- `spec/services/demo/reset_spec.rb` — the reset service and the task gate:
  the re-anchored dates, the published, random and operator passwords, the
  quiet notification bell, and the session-sequence behavior.
- `spec/services/auth/second_factor_policy_spec.rb` — the demo exception.
- `spec/requests/demo_mode_spec.rb` — the credential guards per surface, the
  nil IP, the console step-up, the strip, the credentials block and the
  auth-layout offset.
- `spec/lib/allure/gpx/grade_adjusted_pace_spec.rb` and
  `spec/services/laps/rebuild_spec.rb` — the positionless GAP guard: a
  recording without positions derives its speed intervals with no
  grade-adjusted pace instead of crashing (a bug the demo surfaced).
- Browser (Playwright): the strip, the auto-warning at T−5 without a reload,
  the collision-free auth layout, and a full demo deployment on an isolated
  throwaway project before shipping — never a reset of the development stack.
