# Remote imports contract

A member can link an external account and have its activities imported
automatically. Each provider is operator-enabled, and each is an adapter behind
one registry, one connection model and one batch job. The provider's own terms
apply; the operator documentation carries the warning and the variables.

## 1. Scope and vocabulary

- **Remote import source** — an external service a member links to this
  instance: Garmin Connect, EXR, Withings or Zwift.
- **Connection** — one `ImportConnection` per account and provider, stable
  across re-links.
- **Remote batch** — one listing of a date range, imported entry by entry.
- **Original** — the provider's own file (FIT or TCX), stored like an uploaded
  file.
- **Capability** — what a provider can offer: equipment, MFA, a region, a
  declared sport, a date range.

The file source, the iGPSPORT device source and the Strava archive source are
separate contracts; the Strava archive is always available and needs no
connection.

## 2. Registry and operator gate

`Allure::ImportSources` is the registry. Each remote provider is a key:
`GARMIN_CONNECT`, `EXR`, `WITHINGS`, `ZWIFT`. A provider is offered only while
its variable is set:

| Provider | Variable |
|---|---|
| Garmin Connect | `GARMIN_CONNECT_IMPORT_ENABLED` |
| EXR | `EXR_IMPORT_ENABLED` |
| Withings | `WITHINGS_IMPORT_ENABLED` |
| Zwift | `ZWIFT_IMPORT_ENABLED` |

All four default to off. The operator documentation lists them, the operator
warning and the credential handling; `.env.example` and the production example
document the keys. The application never enables a provider at runtime.

`ImportSources.enabled` is the single gate read by the UI, the batch job and
the admin panels.

## 3. Data model

### 3.1 `import_connections`

| Column | Meaning |
|---|---|
| `user_id` | owner |
| `provider` | `garmin_connect`, `exr`, `withings` or `zwift` |
| `status` | `pending`, `linked`, `expired`, `revoked` |
| `credentials` | encrypted JSON; provider-specific, never rendered, never a job argument |
| `token_expires_at` | when the current session or token ends |
| `external_account_id` | the provider's account id when it has one |
| `region` | `com` or `cn` where the provider has regions |
| `positioned_only` | import only recordings that carry a position (Withings default) |
| `auto_sync` | whether the hourly sync includes this connection |
| `last_synced_at` | last successful sync |
| `last_error` | sanitized error summary |
| timestamps | Rails timestamps |

Unique `(user_id, provider)`. Credentials are encrypted at rest and wiped on
revocation. A connection is owner-scoped; the operator sees its state, never a
credential or the external account's name.

### 3.2 Batches and entries

`workout_import_batches.source` accepts `file`, `strava_archive`,
`garmin_connect`, `exr`, `withings` and `zwift`. A remote batch carries its
`trigger` (`manual` or `scheduled`), the requested `range_from`/`range_to`, a
`paused_until` for a quota pause, and `discovered_at`. Its entries are the
ordinary import entries; an entry the provider cannot import ends `skipped`
with a bounded `skip_reason`.

`workouts.import_connection_id` and `workouts.external_id` keep provenance.
The pair is unique where both are present, so a re-link does not duplicate a
workout.

`users.notify_import_connections` is the single notification switch, on by
default.

## 4. Provider contract

`ImportConnections::Providers` builds an adapter per provider. The adapter
answers:

| Method | Meaning |
|---|---|
| `verify!` | one authenticated call that proves the session; raises `AuthError` when it is refused |
| `list(range)` | the activities in a date range, as `RemoteActivity` values |
| `fetch(remote_activity)` | the original file as a `FetchedActivity` |
| `capabilities` | what the provider offers: equipment, MFA, region, declared sport, date range |
| `equipment` | the provider's gear, when it has any |

A `RemoteActivity` carries the external id, start time, name, sport, duration,
distance, and whether it has a position. A `FetchedActivity` carries a tempfile
holding the original, its filename, its content type, an optional declared
sport and the provider metadata. The adapter never writes a workout; it only
lists and fetches.

`ImportConnections::Providers::CAPABILITIES` hides what a provider lacks: EXR
has no equipment and no fallback sport, Withings declares a sport and imports
positioned sessions by default, Zwift lists the newest 250 activities and
excludes the one still in progress.

`ImportConnections::Linking` holds the request side shared by the providers:
start, code, cancel, stale expiry and the state to return to. A password is
held encrypted on the row only while the link runs and is never a job
argument. The provider's own session or token is what persists.

## 5. Batch job

`Workouts::RemoteImportBatchJob` runs one batch per connection on the
`remote_imports` queue. It lists the range once, then imports each entry
through `Workouts::Importer` with the connection and external id. Deduplication
is by external id, then by a start within ±120 s, then by digest. The quota
pauses the batch (`paused_until`); a refused session expires the connection
(`ImportConnections::Expiry`). An interrupted run can claim the workout it
already committed (`Workouts::ImportResumption`) instead of reporting a
duplicate of itself.

Every job that spends a connection's tokens shares the `ImportConnection`
Solid Queue concurrency group, one at a time per connection.

A remote batch is not a bulk import: its enrichments run at the normal
priority, and automatic publishing may enrol its workouts like a single
upload.

## 6. Shared lifecycle

- **Scheduled sync** — `ImportConnections::SyncAllJob` runs hourly in
  production (`remote_imports_sync`) and `bin/rails remote_imports:sync` runs
  one pass by hand. It syncs linked connections with `auto_sync`.
- **Expiry** — a refused session or token marks the connection `expired`,
  notifies the owner (`import_connection_expired`) and leaves the queued work
  in place. The card offers « Reconnecter et reprendre », whose link job
  resumes the queued batches.
- **Unlink** — `ImportConnections::UnlinkJob` asks whether to keep or delete
  the imported workouts, then wipes the credentials. Deletions go through
  `Workouts::WorkoutDeletion`.
- **Equipment** — `EquipmentSyncJob` imports the provider's gear when the
  provider has any.
- **Account deletion** — the account's connections cascade after a best-effort
  deauthorisation.

## 7. Provider capabilities

| Provider | Original | Equipment | MFA | Region | Declared sport | Notes |
|---|---|---|---|---|---|---|
| Garmin Connect | FIT in a ZIP | yes | yes | `com` / `cn` | no | the session token rotates on refresh |
| EXR | FIT | no | no | — | no | a persistent session credential is kept |
| Withings | TCX synthesized | no | no | — | yes | positioned sessions by default |
| Zwift | FIT | no | no | — | no | newest 250 activities; the one in progress is excluded |

The capability set is catalogue data. Adding a provider is one adapter and one
registry entry, not a new batch job.

## 8. UI and copy

- `/connections` is the area beside the settings, reached from the account
  menu. Its hub lists every service the account may see; each service keeps
  its own page with the connection, the retrieval, the preferences and the
  unlink action. A link or an unlink refreshes that service alone.
- The link form asks for the provider's credentials, with the provider's own
  sentence; a provider with MFA asks for the code. The password is used once
  and never stored.
- The retrieval form offers a date range, a fallback sport and the
  provider's preferences. The import page carries the same panel.
- The batch page names each entry, its state and its translated skip reason.
- The cards poll through `live-frame` only while a link or an unlink runs; a
  fragment with `data-live-frame-done` stops the polling.
- The privacy copy is `DESIGN.md` §19.23–19.24: what is stored, for how long,
  what is deleted, and that the provider's terms apply.
- The iOS companion never renders the API and webhook settings; the
  connections area follows the same native exclusions as the rest of the
  settings.

## 9. Notifications

Two actorless kinds, controlled by `users.notify_import_connections`, created
through `Notifications::Create` with the connection as subject and
`{ "provider" => … }` as payload:

| Kind | When | Text (FR / EN) |
|---|---|---|
| `import_connection_expired` | a refresh is refused or the batch job meets `AuthError` | « %{provider} demande une reconnexion » / "%{provider} needs reconnecting" |
| `import_connection_revoked` | the provider revoked the access, or the operator did | « L'accès %{provider} a été révoqué » / "%{provider} access was revoked" |

Both link to `/connections` and are withdrawn when the connection is linked
again. No notification announces a completed sync: the batch page and the new
workouts already do.

## 10. Administration and metrics

`/admin/imports` lists the batches with their source and trigger, filterable
by status and source; a batch's detail names its source, trigger and requested
range, and gives a skipped entry its translated reason. Its « Connexions » tab
(`/admin/imports/connections`) lists every connection, filterable by provider
and status: owner, provider, state badge, linked at, last sync, session end,
automatic sync, imported workouts, last error. Nothing encrypted is rendered,
and neither is the external account's name or address.

« Révoquer » (`ImportConnections::OperatorRevocation`) is the one mutation: a
linked, expired or pending connection turns `revoked`, its credentials are
wiped, its running batches cancelled, its imported data untouched; the owner
gets `import_connection_revoked` with `{ "by" => "operator" }` and may link
again. It is confirmed, behind the console's second-factor step-up, and
audited as `import_connection_revoked` (metadata: provider, owner).

`/admin/system` lists one flag per provider; the dashboard's imports card adds
« Services connectés : N actifs, M à reconnecter ». `/metrics` exports
`allure_import_connections{provider,status}`,
`allure_import_connection_sync_age_seconds{provider}`,
`allure_import_connection_errors{provider}` and the `source` label on
`allure_import_batches`. No label carries an account name, an external id or a
host.

## 11. Security and privacy negatives

- Credentials and session tokens live only in `import_connections.credentials`,
  encrypted at rest; none is ever a job argument, a log line, a flash, a
  notification payload, a metric label or a rendered value. The settings card
  shows "configured" for a secret, never the secret.
- Remote data never enters a publication snapshot, a Note or any federated
  representation beyond what the workout itself carries once the owner
  publishes it; `external_id`, the connection and the entry metadata stay
  local.
- Privacy zones are not consulted when fetching (the data comes from the
  member's own account) and apply at publication as for any workout.
- A suspended account's connections sync nothing; an operator revocation never
  deletes data.
- Deleting an account cascades its connections after a best-effort
  deauthorisation.
- The pure clients pin their hosts and refuse redirects; a downloaded ZIP goes
  through `Workouts::ArchiveReader`'s path, size and compression checks like an
  uploaded archive.
- No health data is imported: sleep, heart-rate variability and similar
  summaries are ignored.

## 12. Operations

- Environment: the four provider variables, documented in `.env.example` and
  forwarded by `docker-compose.yml`, default off. The production example says
  that these services use sign-ins that may stop working and that the
  provider's terms apply.
- Queues: a `remote_imports` queue is added to the ordinary worker's
  `SOLID_QUEUE_QUEUES` (`config/queue.yml`, `docker-compose.yml`, the production
  Compose); the route-image worker does not take it. The queue carries the
  sync, equipment, link, unlink and remote batch jobs so a slow provider never
  delays file imports or analysis on `default`.
- `config/recurring.yml` gains `remote_imports_sync` (hourly, queue
  `remote_imports`) under production; `bin/rails remote_imports:sync` runs one
  pass by hand.
- No provider needs inbound reachability: every link and every sync is an
  outbound request, so an instance behind a private network works unchanged.
- CI never reaches a provider; the adapters are tested against a fake provider
  and pinned fixtures.

## 13. Tests

- The shared examples (`an import provider`) pin the adapter contract:
  `verify!`, `list`, `fetch`, capabilities and equipment.
- `RemoteImportHelpers::FakeImportProvider` drives the batch job: listing,
  deduplication by external id, start window and digest, quota pause, expiry,
  resumption and cancellation.
- Request specs cover `/connections`, the link and unlink flows, the retrieval
  form, the batch page and the notification switch.
- Admin specs cover the connections tab, the audited revocation and the
  metrics labels.
- No spec contacts a real provider.

## 14. Out of scope

- Uploading to a provider.
- A direct Strava API connection; the archive import is the supported path.
- Health data (sleep, heart-rate variability, body composition).
- A per-account provider preference beyond the connection's own settings.
- A second batch model for remote imports.
