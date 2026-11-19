# Metrics contract

Allure is self-hosted; its operator needs a Grafana view of instance health.
The exporter exposes a Prometheus text endpoint (`/metrics`) scraped by an
external Prometheus or Grafana Alloy and visualized in Grafana. This document
is the binding contract for `/metrics`: metric names, label vocabularies,
semantics, privacy negatives, and deployment. Where it conflicts with
`DESIGN.md`, this document wins — the endpoint is a machine interface with no
visual surface.

## 1. Purpose and scope

- **Format**: Prometheus text exposition 0.0.4, `text/plain; version=0.0.4`.
- **Framework**: Yabeda (`yabeda`, `yabeda-prometheus`, `yabeda-rails`).
  Request metrics come from `yabeda-rails`; Solid Queue, federation, and domain
  gauges are scrape-time `Yabeda.collect!` blocks reading the databases.
- **Not in scope**: OTLP, StatsD, alerting rules, per-query SQL metrics,
  per-authority delivery labels, and any UI. One reference Grafana dashboard
  ships as documentation (§7.1); it is not provisioned by the application.

## 2. Endpoint and access

- `config/routes.rb` mounts `Allure::Metrics::Endpoint` at `/metrics`. The Rack
  endpoint bypasses `ApplicationController`: no session, locale, browser gate,
  CSRF, or layout, exactly like `/up`.
- Access requires `Authorization: Bearer $METRICS_TOKEN`.
  - **Token unset or blank**: 404, indistinguishable from a route that does
    not exist. No aggregates are computed.
  - **Token set, header missing/wrong**: 401 with `WWW-Authenticate: Bearer`.
  - **Token set, header correct**: 200 with `Cache-Control: no-store`.
- The token is compared with `ActiveSupport::SecurityUtils.secure_compare`.
  `METRICS_TOKEN` is documented in `.env.example` and
  `production.env.example` and forwarded by the development and production
  Compose files. It is never rendered in any page, log line, or metric.
- Collection runs only after authorization, so unauthenticated traffic cannot
  drive the aggregate queries.

### Production reachability

Rails is not published on a host port in production. Scrape through the TLS
gateway at `https://$APP_HOST/metrics`; the bearer token is the only
credential. A scraper on the Compose `backend` network must use a Host present
in `ALLOWED_HOSTS`/`APP_HOST`, because `config.hosts` rejects unknown hosts.

### Process model

Request metrics are per web process. Puma runs single-process by default in
this repository; with `WEB_CONCURRENCY > 1`, each worker serves its own
counters and a scraper without sticky sessions sees partial values. The
supported answer is the prometheus-client `DirectFileStore` (documented, not
configured) or a single web process. Database-derived gauges are identical in
every process.

## 3. Metric catalog

All labels are bounded enums, fixed queue names, or short identifiers.
Zero-value series are emitted so panels do not flap.

### HTTP requests — `yabeda-rails`

| Metric | Type | Labels |
|---|---|---|
| `rails_requests_total` | counter | `controller`, `action`, `status`, `format`, `method` |
| `rails_request_duration_seconds` | histogram | same |
| `rails_view_runtime_seconds` | histogram | same |
| `rails_db_runtime_seconds` | histogram | same |

- Controller/action are Rails route targets, never request paths: no IDs, no
  slugs, no query strings.
- `/up` is ignored (`Yabeda::Rails.config.ignore_actions`). `/metrics` is a
  Rack mount, so `yabeda-rails` does not instrument it.

### Background jobs — `allure_jobs_*`

Fixed queue vocabulary: `default`, `ai` (`AI.md`), `federation`,
`federation_media`, `remote_imports` (`REMOTE-IMPORTS.md`), `route_images`,
`webhooks` (`API.md`), `photos` (`PHOTOS.md`); any unknown `queue_name` is
reported under `other`.

| Metric | Type | Labels | Meaning |
|---|---|---|---|
| `allure_jobs_ready` | gauge | `queue` | ready executions |
| `allure_jobs_scheduled` | gauge | `queue` | scheduled executions |
| `allure_jobs_claimed` | gauge | `queue` | claimed (running) executions |
| `allure_jobs_blocked` | gauge | `queue` | blocked executions |
| `allure_jobs_failed` | gauge | `queue` | failed executions |
| `allure_jobs_latency_seconds` | gauge | `queue` | age of the oldest ready execution |
| `allure_jobs_paused` | gauge | `queue` | 1 when the queue is paused |
| `allure_jobs_processes` | gauge | `kind`, `state` | process heartbeats; `state` is `alive`/`stale` |
| `allure_jobs_recurring_last_run_age_seconds` | gauge | `task` | age of the last recurring enqueue |
| `allure_jobs_database_up` | gauge | — | 1 when the queue database answers, 0 otherwise |

The dashboard's « En échec » total is `sum(allure_jobs_failed)`; there is no
separate scalar family, so the suffix reserved for counters is never used on a
gauge. When the queue database is unreachable, only
`allure_jobs_database_up 0` is emitted; every other series is omitted and the
exporter stays available.

### Federation — `allure_federation_*`

| Metric | Type | Labels |
|---|---|---|
| `allure_federation_inbox_items` | gauge | `status` |
| `allure_federation_deliveries` | gauge | `status` |
| `allure_federation_deliveries_open_oldest_age_seconds` | gauge | — |
| `allure_federation_outbox_events` | gauge | `status` |
| `allure_federation_outbox_events_by_activity` | gauge | `activity_type` |
| `allure_federation_remote_notes` | gauge | `status` |
| `allure_federation_remote_segments` | gauge | `status` |
| `allure_federation_media` | gauge | `status` |
| `allure_federation_follows` | gauge | `status` |
| `allure_federation_remote_actors` | gauge | `capability_profile` |
| `allure_federation_blocked_domains` | gauge | — |
| `allure_federation_blocked_actors` | gauge | — |
| `allure_federation_inbox_refusals_total` | counter | `reason` |
| `allure_federation_peer_policies` | gauge | — |
| `allure_federation_retryable_media` | gauge | — |

The refusal counter counts inbound POSTs refused before admission, by
`reason`: `invalid` (401: signature, digest, date, malformed activity),
`unknown_recipient` (404), `blocked` (403), `rate_limited` (429),
`unavailable` (503: the sender's actor could not be fetched). Each refusal
is also logged at warn level with its reason and the claimed actor URI,
never the body.

- `status` is the model's check-constrained enum with zero-filled values
  (`pending, processing, processed, rejected, failed` for inbox items; the
  delivery, outbox, note, course, media, and following enums respectively).
- **No authority, domain, URI, inbox URL, object URI, or actor identifier ever
  becomes a label.** Failure detail stays in the administration console.

### Domain and instance — `allure_*`

| Metric | Type | Labels | Meaning |
|---|---|---|---|
| `allure_info` | gauge | `version` | always 1; build identity |
| `allure_users` | gauge | `state` (`active`, `suspended`) | accounts |
| `allure_users_new_7d` / `_30d` | gauge | — | registrations in the window |
| `allure_users_active_workout_24h` / `_7d` / `_30d` | gauge | — | distinct accounts with a workout created in the window |
| `allure_users_active_publication_7d` / `_30d` | gauge | — | distinct accounts with a publication published in the window |
| `allure_users_active_7d` / `_30d` | gauge | — | union of the two activity definitions |
| `allure_sessions_open` | gauge | — | live session rows (until sign-out, revocation, or expiry — `AUTH.md`) |
| `allure_users_connected` | gauge | — | distinct accounts holding at least one open session |
| `allure_users_second_factor` | gauge | `state` (`satisfied`, `grace`, `required`) | accounts by second-factor obligation (`AUTH.md`) |
| `allure_users_sign_in_methods` | gauge | `method` (`password`, `provider`) | accounts holding a password / at least one provider identity; an account may count in both |
| `allure_workouts` | gauge | — | workouts |
| `allure_workouts_new_7d` / `_30d` | gauge | — | workouts created in the window |
| `allure_workouts_distance_meters` | gauge | — | summed distance |
| `allure_workouts_moving_seconds` | gauge | — | summed moving time |
| `allure_workout_publications` | gauge | `status`, `audience` | workout publications |
| `allure_segment_publications` | gauge | `status`, `audience` | course publications |
| `allure_segments` | gauge | `visibility`, `kind` | reusable courses |
| `allure_segment_efforts` | gauge | — | matched efforts |
| `allure_import_batches` | gauge | `status`, `source` | import batches (`source`: `file` or a remote provider) |
| `allure_import_failed_entries` | gauge | — | failed import entries |
| `allure_import_connections` | gauge | `provider`, `status` | remote import connections (`REMOTE-IMPORTS.md`) |
| `allure_import_connection_sync_age_seconds` | gauge | `provider` | stalest last sync among linked auto-sync connections of an enabled provider; 0 when none |
| `allure_import_connection_errors` | gauge | `provider` | linked connections whose last sync failed |
| `allure_api_tokens` | gauge | `status` | API tokens: `active`, `expired`, `revoked` (`API.md`) |
| `allure_api_requests_total` | counter | `scope`, `status_class` | REST API requests by required scope (`any` before one is checked) and `2xx`…`5xx` |
| `allure_mcp_requests_total` | counter | `method`, `tool`, `outcome` | MCP JSON-RPC requests ([MCP.md](MCP.md)): `method` is `initialize`, `ping`, `tools/list`, `tools/call` or `other`; `tool` a known tool name, `unknown`, or `none` outside `tools/call`; `outcome` `ok`, `not_found`, `invalid` or `error` |
| `allure_webhook_endpoints` | gauge | `status` | webhook endpoints: `active`, `inactive`, `disabled` |
| `allure_webhook_deliveries` | gauge | `status` | webhook deliveries created in the last 24 hours |
| `allure_webhook_delivery_oldest_pending_seconds` | gauge | — | age of the oldest pending delivery; 0 when none |
| `allure_push_subscriptions` | gauge | — | push subscriptions of signed-in companion sessions ([PUSH.md](PUSH.md)) |
| `allure_account_exports` | gauge | `status` | account data exports: `pending`, `running`, `ready`, `failed`, `expired` (`ACCOUNT.md`) |
| `allure_photos` | gauge | `status` | owner photos: `processing`, `ready`, `failed` (`PHOTOS.md`) |
| `allure_photo_bytes` | gauge | — | owner photo originals and derivatives, including bytes reserved by processing uploads |
| `allure_account_deletions_scheduled` | gauge | — | accounts in their deletion window or purge (`ACCOUNT.md`) |
| `allure_workout_weathers` | gauge | `status` | workout weather rows: `pending`, `ready`, `unavailable`, `failed` ([WEATHER.md](WEATHER.md)) |
| `allure_weather_requests_total` | counter | `endpoint`, `result` | Open-Meteo requests: `endpoint` `forecast` or `archive`; `result` `ok`, `unavailable` (429, 5xx or no answer, retried) or `rejected` |
| `allure_push_deliveries_total` | counter | `result` | pushes sent to the relay: `delivered`, `gone` (404/410, subscription deleted), `rejected` (another 4xx, or a relay no longer listed), `failed` (429, 5xx or no answer, retried) |
| `allure_storage_blobs` | gauge | — | Active Storage blobs |
| `allure_storage_bytes` | gauge | — | Active Storage bytes |
| `allure_storage_attachments` | gauge | `record_type` | attachment count (the dashboard's Stockage block) |
| `allure_storage_bytes_by_record` | gauge | `record_type`, `name` | attachment bytes (bounded six owners and their declared names) |
| `allure_database_size_bytes` | gauge | `database` (`primary`, `queue`, `cable`) | on-disk size |

**Active users are activity-based**: a sign-in alone does not count. The
workout, publication, and union queries live in `Users::Engagement`, which the
administration dashboard also calls — a "7-day active user" cannot mean two
different things (see §8). **Connected users are session-based**: a session row
exists only while a device holds a valid session (sign-out and revocation delete
it), so it measures usable sessions, not page views.

### Assistant — `allure_ai_*`

| Metric | Type | Labels | Meaning |
|---|---|---|---|
| `allure_workout_summaries` | gauge | `status` | assistant summary rows: `pending`, `ready`, `failed` ([AI.md](AI.md)) |
| `allure_ai_requests_total` | counter | `kind`, `result` | provider calls: `kind` `summary` (the conversation adds `chat`); `result` `ok`, `invalid` (schema or verification), `rejected` (a terminal 4xx) or `unavailable` (429, 5xx, timeout, retried) |
| `allure_ai_request_duration_seconds` | histogram | `kind` | one provider call, from the request to the last byte |
| `allure_ai_tokens_total` | counter | `kind`, `direction` | tokens the answer's `usage` reported: `prompt` and `completion`; nothing when the endpoint reports none |

Never a prompt, an answer, a fact, a model alias or an endpoint host: the
labels are closed vocabularies like every other family here.

### Ruby process — `allure_process_*`

| Metric | Type | Meaning |
|---|---|---|
| `allure_process_start_time_seconds` | gauge | process start (Unix time) |
| `allure_process_resident_memory_bytes` | gauge | RSS where `/proc` is available |
| `allure_process_threads` | gauge | live threads |
| `allure_gc_count` | gauge | `major`/`minor` label, GC counts |
| `allure_gc_live_slots` | gauge | GC live slots |

### Derived-data rebuild timing — `allure_best_efforts_*`

| Metric | Type | Labels | Meaning |
|---|---|---|---|
| `allure_best_efforts_rebuild_duration_seconds` | histogram | `phase`, `context` | duration of one `BestEfforts::Rebuild` phase |

- `phase` is `compute` (pure Ruby over the track points, run before the
  caller's transaction) or `persist` (the row replacement inside it);
  `context` is `import`, `reanalysis`, `backfill`, or `credit` (a credit row
  rebuilt from its source, `SHARED-ACTIVITIES.md`). Both answer the same
  question the lock investigation asked: how much work actually runs under the
  `workouts`/`users` write lock.
- No workout, account, or sport identifier is a label; durations are the only
  exported value. Buckets span 1 ms to 60 s, the range a persist or a full
  point scan can occupy.

## 4. Collection and caching

- `Metrics::Snapshot` computes every database-derived value in one pass;
  `Metrics::Cache` memoizes it for `Metrics::CACHE_TTL = 15.seconds` behind a
  `Mutex`. A scrape inside the TTL is nearly free; a scrape after it pays the
  grouped counts once.
- Each family is rescued independently. A failure (queue database down, slow
  query) omits that family and reports through `Rails.error`; the exporter
  never returns 500 and never raises into `Yabeda.collect!`.
- Counts are bounded by check-constrained enums; the only joins are indexed
  (`workouts.user_id`, `sessions.user_id`, attachment blobs). No query lists
  users, domains, or identifiers.

## 5. Privacy negatives

The rendered exposition must never contain:

- GPX coordinates, track points, or sanitized-representation payloads;
- private keys, signatures, raw inbox bodies, or remote HTML;
- secrets, credentials, tokens, or environment values;
- remote domains, inbox URLs, actor URIs, handles, usernames, emails, short
  IDs, UUIDs, object URIs, job class arguments, or error messages.

`allure_info` carries only `Allure::VERSION`; `allure_database_size_bytes`
carries only the role name. A spec asserts that fixtures with distinctive
usernames, domains, and short IDs never appear in the response body.

## 6. Testing

- Request specs prove 404 while disabled, 401 for missing/wrong tokens, and a
  parseable exposition with the token.
- Snapshot specs assert each family's values against real rows, including the
  queue-database-down fallback and the activity windows.
- Process-global Yabeda values are reset between examples
  (`spec/support/yabeda.rb`), so request-metric assertions never depend on
  example order.
- The privacy negative spec renders the exposition after creating data whose
  identifiers would be distinctive if leaked.

## 7. Operations

```yaml
# prometheus.yml
scrape_configs:
  - job_name: allure
    scheme: https
    metrics_path: /metrics
    authorization:
      credentials: ${METRICS_TOKEN}
    static_configs:
      - targets: ["allure.example.com"]
```

- Grafana adds Prometheus (or Alloy) as a datasource, then imports the
  reference dashboard (§7.1).
- Rotating `METRICS_TOKEN` takes effect on the next request (read at call
  time); no restart is required.
- `/metrics` requests are logged by the Rails request logger like any other
  request; operators who want silence can adjust their log pipeline.

### 7.1 Reference dashboard

`docs/grafana/allure.json` (« Allure — Instance », uid `allure-instance`) is
imported through Grafana's *Dashboards → Import*. It carries no alert. Its
variables are the Prometheus `datasource`, `job` and `instance` (read from
`allure_info`), and `queue`; every panel reads `${datasource}`. A version
change is annotated from `allure_info{version}`. Its titles and
descriptions are in English, like the operator documentation.

Rows, top to bottom:

1. **Instance health** — version, uptime, queue database, alive and stale
   workers, `sum(allure_jobs_failed)`, the oldest open federation delivery,
   the 5xx rate.
2. **HTTP** — requests by status, p50/p95/p99 latency, the ten slowest
   controller actions, DB and view p95, the 5xx ratio.
3. **Background jobs** — ready, running, scheduled, blocked, failed and latency
   per queue, paused queues, processes, recurring tasks' last run.
4. **Federation** — open and terminal deliveries, outbox and inbox statuses,
   remote media, the outbox by activity type, follows, remote actors, blocks,
   peer policies, remote notes and courses.
5. **Usage** — accounts, activity-based active users, connected accounts,
   workouts and their totals, daily creations, workout and course
   publications, courses by kind and visibility.
6. **Imports and connections** — batches by source and status, failed entries,
   connections by provider and status, sync age, connection errors.
7. **API, MCP, webhooks and push** — REST requests by status class and scope,
   MCP tool calls, webhook deliveries and backlog, tokens and endpoints, push
   results and subscriptions.
8. **Authentication** — second-factor obligation and sign-in methods.
9. **Resources** — database and storage sizes, storage by owner, Ruby
   process and GC, the best-efforts rebuild p95.

Every gauge is a current state: trends use `delta`/`deriv`, never
`rate`/`increase`, which are reserved for the `_total` counters and the
histograms. `spec/services/metrics/grafana_dashboard_spec.rb` fails when a
panel queries a family `Metrics::Catalog` does not export, so a metric rename
updates the dashboard in the same patch.

## 8. Administration console correspondence

The exporter and `/admin` are not identical views, but an operator must
recognize the same concept under the same words. Every exported gauge declares
its console counterpart in `Metrics::Catalog`; the mapping is enforced by specs,
so a new gauge cannot land without deciding what it corresponds to.

| Console label (FR / EN) | Console source | Metric family | Notes |
|---|---|---|---|
| Comptes / Accounts | `admin.dashboard.accounts.title` | `allure_users{state}` | the tile total is `sum(allure_users)`; the metric adds the `suspended` split |
| +X cette semaine / this week | `admin.dashboard.trend` | `allure_users_new_7d/30d`, `allure_workouts_new_7d/30d` | same 7 d/30 d windows |
| X connectés / connected | `admin.dashboard.accounts.activity` | `allure_users_connected`, `allure_sessions_open` | a session is open until sign-out, revocation, or expiry |
| Double authentification / Two-step verification | `admin.accounts.second_factor` | `allure_users_second_factor{state}` | the account page states one account's obligation; the metric counts them |
| Connexion / Sign-in | `admin.accounts.sign_in_methods` | `allure_users_sign_in_methods{method}` | the account page names one account's methods; the metric counts accounts per method |
| Y actifs cette semaine / active this week | `admin.dashboard.accounts.activity` | `allure_users_active_7d` | activity-based union (workout or publication); the metric also exposes 24 h/30 d and the two components, the tile only 7 d |
| Activités / Workouts | `admin.dashboard.workouts.title` | `allure_workouts`, `allure_workouts_distance_meters`, `allure_workouts_moving_seconds` | the tile formats distance/duration for the viewer, the metric is SI |
| Publications actives / Active publications | `admin.dashboard.publications.title` | `allure_workout_publications{status,audience}` | same status/audience enum values |
| Parcours / Courses (onglet Publications) | `admin.publications.tabs.courses` | `allure_segment_publications{status,audience}`, `allure_segments`, `allure_segment_efforts` | the metric keeps the model vocabulary (`segment`) while the console labels the tab « Parcours/Courses » |
| Acteurs distants / Remote actors | `admin.dashboard.federation.title` | `allure_federation_remote_actors{capability_profile}` | the tile is the total, the metric splits by capability |
| abonnements / accepted · demandes / pending | `admin.dashboard.federation.follows` | `allure_federation_follows{status}` | `accepted` is the model status behind the word « abonnement » |
| Publications distantes / Remote publications | `settings.federation.activity.notes` | `allure_federation_remote_notes{status}` | same enum |
| Parcours distants / Remote courses | `settings.federation.activity.segments` | `allure_federation_remote_segments{status}` | same enum |
| Événements en cours de livraison / outbox events | `admin.dashboard.federation.outbox` | `allure_federation_outbox_events{status}` | the tile is the sum of `preparing/pending/expanded` |
| Livraisons en cours / deliveries in flight | `admin.dashboard.federation.deliveries` | `allure_federation_deliveries{status}` | the tile is the sum of the open statuses |
| Plus ancienne livraison / oldest delivery | `admin.federation.health.oldest` | `allure_federation_deliveries_open_oldest_age_seconds` | seconds vs the console's relative wording |
| Activité entrante / inbound activity | `settings.federation.activity.inbox` | `allure_federation_inbox_items{status}` | same enum |
| Médias / media | `settings.federation.activity.media` | `allure_federation_media{status}` | note and course attachments merged, same as the console |
| Domaines bloqués / blocked domains | `settings.federation.blocks.domains` | `allure_federation_blocked_domains` | the console lists domains, the metric counts them (never a label) |
| Acteurs bloqués / blocked actors | `settings.federation.blocks.actors` | `allure_federation_blocked_actors` | idem |
| Politiques de pairs / peer policies | `settings.federation.policies.title` | `allure_federation_peer_policies` | idem |
| Médias à relancer / retryable media | `settings.federation.media.title` | `allure_federation_retryable_media` | same `failed` + `unavailable` definition |
| Stockage / Storage | `admin.dashboard.storage.title` | `allure_storage_blobs`, `allure_storage_bytes`, `allure_storage_attachments{record_type}`, `allure_storage_bytes_by_record{record_type,name}` | `record_type` values are the underscored i18n keys (`workout`, `workout_publication`, …); `name` is a metric-only dimension |
| Fichiers importés / imports | `admin.dashboard.imports.failed`, `admin.imports.title` | `allure_import_failed_entries`, `allure_import_batches{status,source}` | same entry/batch statuses and the panel's source filter |
| Connexions aux services / service connections | `admin.imports.connections.title` | `allure_import_connections{provider,status}`, `allure_import_connection_sync_age_seconds{provider}`, `allure_import_connection_errors{provider}` | same provider and status values as the tab's filters; the tab shows each connection, the metrics count them |
| API et webhooks / API and webhooks | `admin.accounts.api.tokens`, `admin.accounts.api.webhooks` | `allure_api_tokens{status}`, `allure_webhook_endpoints{status}`, `allure_webhook_deliveries{status}`, `allure_webhook_delivery_oldest_pending_seconds` | the account page lists one account's tokens and endpoints, the metrics count every account's; never a host, an account or a token |
| Sur cet iPhone / On this iPhone | `settings.notifications.push.title` | `allure_push_subscriptions` | the card shows one session's device, the gauge counts every session's; never an endpoint, a device or an account |
| Export des données, suppression programmée / Data export, deletion scheduled | `admin.accounts.export.title`, `admin.accounts.states.deletion_scheduled` | `allure_account_exports{status}`, `allure_account_deletions_scheduled` | the account page shows one account's last export and date, the metrics count every account's; never an account, a size or a date |
| Photos / Photos | `photos.admin.title` | `allure_photos{status}`, `allure_photo_bytes` | the account page shows its quota and usage; metrics aggregate all accounts without identifiers |
| Météo / Weather | `admin.jobs.weather.title` | `allure_workout_weathers{status}` | the panel shows the 24-hour request budget and the pending count, the gauge counts every row by status; never a workout, an account or a position |
| Synthèses / Summaries | `admin.jobs.summaries.title` | `allure_workout_summaries{status}` | the panel shows the pending count and the day's requests against the cap, the gauge counts every row by status; never a workout, a member, a fact or a model answer |
| Tâches de fond / Background jobs | `admin.jobs.*` | `allure_jobs_*` | queue/process/latency/paused labels match the panel columns; the « En échec » total is `sum(allure_jobs_failed)` |
| Bases de données / Databases | `admin.system.databases` | `allure_database_size_bytes{database}` | same `primary/queue/cable` roles |
| Version | `admin.system.versions` | `allure_info{version}` | likewise |

### Intentional differences

- **Not exported**: failing-authority domains, blocked-domain/actor lists,
  per-publication delivery rollups, recent lists (accounts, publications,
  imports, audit), job error messages and arguments. They are unbounded or
  identifying; the console remains the place to read them.
- **Not shown in the console**: HTTP request metrics (`rails_*`), Ruby
  process/GC (`allure_process_*`, `allure_gc_*`), the best-efforts rebuild
  histogram (`allure_best_efforts_rebuild_duration_seconds`), the outbox split
  by activity type, and active-user windows of 24 h/30 d. They are technical or
  detailed views with no panel counterpart.
- **Unknown queues** are displayed as-is by the jobs panel but folded into
  `queue="other"` in the exposition, so the label stays bounded; also, the
  panel does not zero-fill known queues while the metric does.
- **Recurring tasks** never enqueued are omitted by the metric (the panel shows
  « never »).
- `record_type` label values are the underscored translation keys; an owner with
  no `admin.dashboard.storage.record_types` entry fails the guard spec.

## 9. Funding contributions

`allure_funding_contributions{provider,tier,status}` counts voluntary
contributions and corresponds to `/admin/funding`. It is entirely absent while
`FUNDING_ENABLED` is false, including previously collected samples. Counts use
the ordinary 15-second Snapshot cache. Labels are closed: provider is `manual`,
`stripe`, `helloasso` or `other` (custom adapters); tier is `coffee`, `beer` or
`energy`; status is `active`, `upcoming`, `expired` or `revoked`. A paid
period whose `starts_at` is in the future is `upcoming`, not an active badge.
Revocation takes precedence over expiry and a future start. No amount, account
identifier, external payment ID or provider payload enters the exposition. See
[FUNDING.md](FUNDING.md).
