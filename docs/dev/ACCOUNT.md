# Account contract

Members get two account controls: a complete, re-importable copy of their
data, and the deletion of their account without asking the operator. This
document defines the export archive, the seven-day deletion window, the
resumable purge and the operator's part. `DESIGN.md` governs the copy; where
the two conflict on a data, privacy or federation contract, this document
wins.

## 1. Product decisions

1. **Web only.** Neither the export nor the deletion has a REST, MCP or
   webhook surface (`API.md` lists account deletion as web-only). Both live on
   `/settings/account`, which the iOS companion renders like any settings
   page.
2. **The export is a complete, open archive.** One ZIP holds the original
   files exactly as imported, and everything else as JSON and CSV in SI
   units. Its sessions, with their IP address and device, are included: they
   are personal data the account has a right to read. No secret ever is.
3. **The originals re-import as they are.** They travel as nested ZIP
   archives of at most 1 000 files (`Workouts::ArchiveReader`'s entry cap), so
   each one can be dropped on the import page of any Allure instance.
4. **Deletion waits seven days.** The request deactivates the account at once
   and schedules the deletion; signing in during the window lands on a single
   page offering to cancel it. Nothing federates during the window, because a
   withdrawn publication can never be restored (republishing mints a new
   identity, `PUBLISHING.md`).
5. **Deletion is the signed withdrawal, then a resumable purge.** The
   existing lifecycle (`Federation::ActorDeletion`) runs first; the rows and
   blobs are then removed in batches by a job that resumes where it stopped.
6. **A deleted username is never handed out again.** The tombstoned actor
   keeps its URI forever (it answers 410), and the URI is derived from the
   username, so a new account with that name could never federate.
7. **The operator cannot delete their own account** from the web, as they
   cannot suspend it; the console remains. The operator may schedule (and
   cancel) another account's deletion from `/admin/accounts/:id`, with the same
   window, audited.

## 2. Making deletion safe

### 2.1 Reserved usernames

`User` validates that no local actor other than its own already carries the
actor URI its username derives (`Allure::Federation.config.actor_uri`),
tombstoned or not. The validation runs on every create path: registration,
invitations, the provider onboarding and `users:create`. Error copy:
`activerecord.errors.models.user.attributes.username.retired`.

### 2.2 `Users::DeleteAccount`, resumable

`call!(limit: nil)` runs the phases in order, each idempotent and each
skipped once done; it answers `true` when the user row is gone and `false`
when `limit` workouts were deleted and work remains (the job re-enqueues).

| Phase | What happens | Done when |
|---|---|---|
| `cut_off` | `deletion_started_at` set; sessions, push subscriptions, API tokens, recovery codes, passkeys and identities deleted; import connections and their credentials deleted; queued imports and bulk operations cancelled; webhooks stay but deliver nothing for a deactivated account and cascade with the row | `deletion_started_at` present |
| `funding` | every live provider subscription matched to the account — including one bound by a late verified checkout notification during the window (`Funding::Reference.resolve for_billing:`, [FUNDING.md](FUNDING.md)) — is cancelled at the provider (renewal stopped; paid periods retained); billing identifiers are purged only with the rows at the end | every live subscription answered `canceled` / confirmed `cancel_at_period_end`, or none existed; an unexplained provider 404 blocks the phase fail-closed with the billing identifiers intact |
| `federation` | live participations withdrawn, then `Federation::ActorDeletion` (publications withdrawn, comments taken out, signed actor `Delete`, tombstone) | actor absent or tombstoned |
| `workouts` | `Workouts::WorkoutDeletion` one by one, at most `limit` per call: participants' credit rows are detached, segment counters refreshed, blobs purged later | no workout left |
| `rest` | `@user.destroy!` cascades the remaining small rows (segments, equipment, profiles, zones, records, exports, notifications) | row gone |

Once `deletion_started_at` is set the deletion can no longer be cancelled.
`Users::AccountPurgeJob` (queue `default`, one per account through a
concurrency key) calls `call!(limit: 50)` and re-enqueues itself while work
remains. The audit row `account_deleted` (`AdminEvent`, metadata
`username` and `by`: `self` or `operator`) is written when the purge starts,
with no subject, so it survives the row.

## 3. Data export

### 3.1 Model

`AccountExport`: `user_id` (cascade), `uuid` (ShortUUID in URLs), `status`
(`pending`, `running`, `ready`, `failed`, `expired`), `archive` (Active
Storage), `byte_size`, `counts` (JSON object), `error_code`, `started_at`,
`completed_at`, `expires_at`. A partial unique index allows one `pending` or
`running` export per account. A new export may be requested once every 24
hours (`AccountExport::COOLDOWN`); a ready export lives 7 days
(`AccountExport::LIFETIME`).

### 3.2 Job

`Users::ExportJob` (queue `default`) writes the archive with
`Zip::OutputStream` into a temporary file (Zip64), copying each original blob
one at a time through `blob.open`, attaches it, marks the row `ready`, and
tells the account: an in-app `account_export_ready` notification (always
created: the account asked for it, so no switch) and an e-mail
(`AccountMailer#export_ready`). A failure marks the row `failed` with an
error code and mails nothing. `Users::AccountExportSweepJob` (daily) marks
past-due exports `expired` and purges their archive.

### 3.3 Contents (`export_version: 1`)

| Path | Contents |
|---|---|
| `LISEZMOI.txt`, `README.txt` | what the archive holds, units, how to re-import |
| `account.json` | profile, preferences, leaderboard category, notification switches, enrolled factors (kind and date), linked identity providers (provider and date), import connections (provider, status, dates) |
| `sessions.json` | open sessions: device, IP address, sign-in method, created, last seen |
| `workouts/index.csv`, `workouts/index.json` | one row per workout: the REST `Workout` detail representation (`API.md`) |
| `assistant.json` | the account's assistant summaries ([AI.md](AI.md)): per workout its locale, proposed title, sentences, model and date — never the facts snapshot |
| `workouts/originals-NNN.zip` | the original files, 1 000 per archive, named `<date>_<id>.<ext>` |
| `records.json` | the seven classic records, best efforts and effort records |
| `segments.json`, `segments.geojson` | the account's own segments, with their elevation profile |
| `equipment.json`, `publishing_profiles.json` | catalog representations |
| `privacy_zones.geojson` | the zones (they are the account's own data) |
| `publications.json` | every publication snapshot the account published, live or withdrawn |
| `social/following.csv`, `social/followers.csv` | Mastodon's `Account address` format |
| `social/comments.json`, `social/reactions.json` | what the account wrote or gave |
| `avatar.webp` | the uploaded avatar, when there is one |

Every CSV line goes through `Allure::CsvCell`: a text cell starting with `=`,
`+`, `-`, `@`, a tab or a carriage return gets a leading `'`, because some of
that text comes from other instances (a credit row's title, a remote account
address) and a spreadsheet would otherwise evaluate it as a formula. Numbers
are never prefixed; the JSON files keep every value as it is.

Never exported: the password digest, the TOTP secret, recovery codes, passkey
keys, API token digests, webhook secrets, import-connection credentials, the
actor's private key, session tokens, and any other account's content beyond
their handle.

### 3.4 Access

The « Exporter mes données » card requires a recent proof of identity to
request an export. The download goes through
`GET /settings/account/exports/:id/download`, owner-scoped, streamed, never a
raw Active Storage URL, and answers 404 once expired.
`/admin/accounts/:id` shows the last export's state, never its contents.
`/metrics` exports `allure_account_exports{status}` and
`allure_account_deletions_scheduled`.

## 4. Self-service deletion

### 4.1 Request

The « Supprimer mon compte » card states what leaves and what stays, offers
the export first, and asks for a recent proof of identity, the username typed
again and an acknowledgment. The request sets
`users.deletion_requested_at` and `users.deletion_scheduled_at` (+7 days,
`Users::DeletionSchedule::GRACE`), records who asked
(`deletion_requested_by`: `self` or `operator`), closes every other session
(the current one lands on the deactivated page), and mails the date
(`AccountMailer#deletion_scheduled`).

### 4.2 The window

During the seven days the account is **deactivated** (`User#deactivated?`,
which `suspended?` also implies):

- every page redirects to `/settings/account/deletion`, which offers
  « Annuler la suppression », the last export when one is ready, and sign-out;
- its publications and courses are hidden locally and refused on the wire
  (`WorkoutPublication.visible_to`, `Workouts::PublicationPolicy`,
  `Segment.readable_by`, the profile page);
- no notification, push, webhook, synchronisation, automatic publication or
  co-presence detection runs, as for a suspended account (`User#deactivated?`
  replaces `suspended?` at those gates); API tokens are refused with the
  `account_deletion_scheduled` problem (`API.md`);
- nothing federates: remote copies stay until the deletion runs. A due
  scheduled publication waits at its `scheduled_for` until the window is
  cancelled — the publication policy would refuse its deliveries anyway — and
  the purge cancels it with its workout.
- a verified funding checkout notification that arrives during the window
  still binds its subscription to the account as billing owner — no badge, no
  notification — so the purge's cancellation reaches it; once the purge has
  started, the notification cancels the renewal at the provider immediately
  ([FUNDING.md](FUNDING.md)). While the window is open the subscription stays live,
  so a cancelled deletion keeps it.

Cancelling clears the three columns and mails a confirmation
(`AccountMailer#deletion_cancelled`); closed sessions do not come back. A
deletion the operator scheduled can only be cancelled by the operator: the
deactivated page says so and offers no cancel button. An account whose purge
has started is signed out on its next request.

### 4.3 Execution

`Users::AccountDeletionSweepJob` (hourly) enqueues `Users::AccountPurgeJob`
for every account whose `deletion_scheduled_at` has passed, including a purge
that stopped half-way. The final e-mail (`AccountMailer#deleted`) is sent
with the address and locale captured before the purge, never with the row.
The purge demands the schedule it was enqueued for: cancelled between the
sweep's guard and the cut-off, the cut-off raises `DeleteAccount::Cancelled`
under the row lock and the job stops, so a confirmed cancellation always
wins.

### 4.4 Operator

`/admin/accounts/:id` shows the scheduled date and offers « Programmer la
suppression » and « Annuler la suppression » (audited
`account_deletion_scheduled`, `account_deletion_cancelled`). The operator's
own account offers neither.

## 5. Verification

- Request specs: proof of identity, the operator refusal, 404 on another
  account's export, expiry, the deactivated page, cancellation.
- Service specs: archive contents and the absence of every secret, chunked
  originals and their re-import, purge resumption, the reserved username,
  participants' credit rows detached.
- Browser: both flows, French and English, desktop and phone.
