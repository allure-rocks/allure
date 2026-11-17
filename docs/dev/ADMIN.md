# Administration contract

A self-hosted instance has exactly one owner. The console turns the routine
administration tasks into a first-class, audited surface:

- instance metrics at a glance (dashboard);
- background-job health with live updates and recovery controls;
- federation health and safety controls;
- publication oversight and takedown;
- account administration: suspension and invitations;
- import failure inspection;
- system diagnostics;
- an audit log of every operator action.

It is explicitly **not** a multi-tenant moderation system. Reports, appeals,
moderator roles, per-account blocks, and notification surfaces are out of scope
(`[devdoc:roadmap]`).

## 1. Purpose and scope

The console at `/admin` is the operator-only administration surface. Where it
conflicts with `DESIGN.md`, this document wins for data, authorization, and
privacy contracts; `DESIGN.md` wins for visual and interaction detail where
this document is silent.

## 2. Identity and authorization

- The operator is `User#instance_operator?`: the single account named by
  `INSTANCE_OPERATOR_USERNAME` (case-insensitive, stripped). Unset means nobody
  is an operator. There are no roles, no promotion UI, and no persisted admin
  flag.
- Because the role is a name comparison, self-registration refuses the
  configured operator name (`User` validates it as reserved in the
  `:self_registration` context) so an open instance whose operator account is
  not created yet cannot have the name claimed by the first visitor. The
  refusal also covers invitation sign-ups, which go through the same
  registration form; the operator account is created from the console
  (`users:create`), which is unaffected.
- Every admin route lives under `Admin::BaseController`, whose
  `before_action :require_operator` raises `ActiveRecord::RecordNotFound`.
  Non-operators get the standard **404**, never a 403: the console's existence
  is never confirmed.
- `config/navigation.rb` declares the console menu as a `position: :admin`
  section. `NavigationHelper#visible_nav_items` hides every leaf from
  non-operators through `policy: :instance_operator?`, and the product chrome
  (`layouts/_topbar`, the bottom bar, the settings shell) never renders the
  admin section.
- The only product-chrome entry point is the account dropdown's
  « Administration » item, rendered exclusively when `instance_operator?` is
  true. A member's HTML never contains an admin link.
- The `/settings/federation` URL keeps requiring the operator and redirects to
  `/admin/federation`; the settings hub and subnav no longer list the
  federation controls.

## 3. Shell

- `Admin::BaseController` renders `layout "admin"`.
- The admin layout keeps the Tabler shell and the single Vite entrypoint, the
  server-selected theme, CSRF tags, the skip link, flash, toasts, the shared
  confirm modal, and the release-notes dialog (the footer version trigger must
  never be dead). It deliberately omits the product primary navigation, the
  phone bottom bar, and the feedback widget.
- The admin topbar carries the brand mark with an « Administration » badge,
  the admin menu tree (horizontal, collapsing behind the hamburger below
  `lg`), the theme toggle, a « Retour à Allure » link to `/me`, and the shared
  account menu with the self-link suppressed.
- The standard footer is kept, so instance identity and the version line stay
  visible.
- Each admin page follows the product page anatomy: `content_for :title`,
  `content_for :page_header` with the « Administration » pretitle and exactly
  one `<h1>`, then `.row.row-deck.row-cards` cards and `DESIGN.md` §12 tables.

## 4. Panels

### 4.1 Dashboard — `/admin`

`Admin::Dashboard::Overview` returns a `Data` result of counts and bounded
top-5 lists:

- accounts: total, new in 7 and 30 days;
- workouts: total, new in 7 and 30 days, summed distance and moving time;
- publications: active workout publications, public vs followers split, active
  course publications, failed import entries;
- federation: remote actors, accepted follows, pending follow requests, active
  remote notes and courses, open outbox events, in-flight deliveries;
- storage: Active Storage blob count, total bytes, attachment counts by record
  type;
- queue: ready, scheduled, and failed Solid Queue executions. When the queue
  database is unreachable the card says so and the rest of the page still
  renders;
- recent lists: latest accounts, publications, imports, and audit events.

The dashboard ships metric tiles and period deltas; charts are out of scope
(§11). The Prometheus exporter mirrors these numbers under the same concepts;
the family-by-family mapping and the intentional differences live in
`METRICS.md`, and the account activity/connection definitions are shared
through `Users::Engagement` so the two surfaces cannot drift.

### 4.2 Jobs — `/admin/jobs`

Live panel built on `Admin::Jobs::Snapshot`:

- per queue: ready, scheduled, claimed, blocked, and failed counts plus
  latency, and whether the queue is paused;
- processes: workers, dispatchers, and schedulers with kind, host, heartbeat
  age, alive state, and pool metadata;
- recurring tasks: key, schedule, last enqueued, next run (production only);
- failed executions: the 20 most recent, with job class, queue, error class,
  message, and failed time;
- next scheduled executions;
- maintenance: the count of workouts on an older analysis version, computed on
  page load rather than in the polled fragment.

Updates poll every 4 seconds through the `live_frame_controller` Turbo Frame
fragment (`Turbo-Frame` request header, `Cache-Control: no-store`), suspended
while the tab is hidden and aborted on Turbo disconnect. No Action Cable.

Mutations, each audited:

- retry one failed execution (`SolidQueue::FailedExecution#retry`);
- discard one failed job;
- retry all failed executions, and discard all failed executions (destructive,
  shared confirm modal);
- pause and resume a queue;
- enqueue the versioned rebuild sweep when workouts are stale
  (`Workouts::BackfillRebuildJob`, self-rescheduling in bounded batches),
  which re-reads the original file once to reconcile the import facts, the
  analysis, the places and the owner route image (`DERIVATIONS.md`), audited
  with the affected count;
- enqueue the owner route-image sweep (`Workouts::BackfillRouteImagesJob`) for
  missing or stale images, audited with the affected count; publication images
  are snapshot media and out of scope;
- enqueue the places backfill and, when a provider is configured, the terrain
  elevation backfill, each audited with the affected count.

Each sweep is idempotent, safe to re-run, and its card shows the pending count
or "à jour". The same rebuilds are available owner-scoped on `/settings/data`
(`DERIVATIONS.md`).

### 4.3 Federation — `/admin/federation`

The federation panel at `/admin/federation`:

- inbox items by status, per-authority delivery counts, remote note/course
  statuses, combined media counts, retryable media;
- delivery health: open deliveries and oldest pending age;
- pending follow requests aggregate;
- domain and account blocks (create/remove);
- peer policies (promote/demote/remove);
- remote media retry.

Every existing mutation records an `AdminEvent`. The privacy contract is
unchanged: counts and identifiers only — never coordinates, payloads, keys,
inbox bodies, or remote HTML.

### 4.4 Publications — `/admin/publications`

- Two tabs: workout publications and course publications.
- Columns: owner, title or course name, sport, audience, status, publication
  time, delivery summary (delivered / open / failed), and sanitized media size.
- Filters: status, audience; Pagy pagination.
- Takedown: withdrawing an active publication uses the existing immutable
  lifecycle (`Workouts::PublicationWithdrawal`,
  `Segments::PublicationWithdrawal`) with an explicit `operator:` path checked
  *inside* the service (`user.instance_operator?`), so the owner-only
  authorization is never weakened. A confirm modal states the consequences
  (the publication is withdrawn for every viewer; the owner keeps the
  workout); the audit event records the kind, owner, and audience.

### 4.5 Accounts — `/admin/accounts`

- Index: search by username or email, creation date, locale, suspension state,
  operator badge, and per-account counts (workouts, active publications,
  storage bytes). Pagy pagination.
- Detail: account metadata, federation actor (acct, capability, tombstone
  state), sessions and last seen, activity and storage counts.
- Suspend: sets `suspended_at` and `suspension_reason`, destroys every session,
  and audits. Reinstate clears both. The operator cannot suspend themselves.
- A suspended account cannot sign in (`SessionsController#create` rejects the
  credentials after verification with a dedicated message) and any session
  cookie is ignored and destroyed by the authentication concern. Content the
  account already published is not withdrawn; suspension revokes access only.

### 4.6 Invitations — `/admin/invitations`

- List: email (and display name when set), created, expires, accepted state;
  revoke with confirmation.
- Create: email, an optional display name (≤ 60 characters, prefilled in the
  password sign-up form and the provider onboarding, editable by the invitee,
  `NAME=` for `users:invite`), plus expiry (default 7 days, capped at 30); an
  email that already has an account is rejected. Only the token digest is
  stored, so the single-use URL is rendered exactly once on the creation
  response, with copy affordance, and cannot be recovered later.
- No email is sent; the operator shares the link.

### 4.7 Imports — `/admin/imports`

- Batch list: owner, status, imported/failed/duplicate/cancelled counters,
  created time; Pagy pagination.
- Batch detail: per-entry status, detected type, fallback sport, and the stored
  parser `error_message`.
- Remote sources (`REMOTE-IMPORTS.md`): the list gains the source filter and
  the trigger column, the detail the requested range and the skip reasons, and
  a « Connexions » tab (`/admin/imports/connections`) lists every connection
  with the audited « Révoquer » (`import_connection_revoked`).

### 4.8 System — `/admin/system`

- Versions: `Allure::VERSION`, Ruby, Rails, Solid Queue, PostgreSQL, PostGIS.
- Database sizes: primary and queue databases, human-readable.
- Storage: blob count and bytes, attachment counts by record type.
- Environment flags and identity: registration open, restricted federation
  enabled, operator configured, SMTP configured (boolean only), one flag per
  remote import source, federation base URL and domain, instance name and
  optional host.
- No secret value is ever rendered.

### 4.9 Audit log — `/admin/events`

Paginated, newest first: time, actor, translated action, subject, and
metadata summary; filter by action. Read-only.

## 5. Audit log contract

- `admin_events` is the durable record: `user_id` (nullable, nullified if the
  actor is deleted), `action` (DB check against `AdminEvent::ACTIONS`),
  polymorphic `subject`, `metadata` jsonb object, timestamps.
- Rows are append-only. The model raises on update; there is no delete path.
- `Admin::Audit.record(actor:, action:, subject: nil, metadata: {})` is the
  only write seam. Every mutation in §4 records exactly one event; metadata is
  aggregate and non-secret (domains, queue names, counts, reasons supplied by
  the operator) and never contains payloads, coordinates, keys, or raw
  bodies.
- Actions: `domain_blocked`, `domain_unblocked`, `actor_blocked`,
  `actor_unblocked`, `peer_policy_set`, `peer_policy_removed`, `media_retried`,
  `job_retried`, `job_discarded`, `jobs_retried`, `jobs_discarded`,
  `queue_paused`, `queue_resumed`, `publication_withdrawn`,
  `account_suspended`, `account_reinstated`, `invitation_created`,
  `invitation_revoked`, `account_deletion_scheduled`,
  `account_deletion_cancelled`, and `account_deleted` (written by the purge
  itself, with no operator and no subject, `ACCOUNT.md`).

## 6. Privacy boundaries

The console is the one place technical delivery state and provider jargon may
appear (`FEDERATION.md`), but it still never exposes:

- GPX coordinates, track points, or sanitized-representation payloads;
- private keys, signatures, raw inbox bodies, or remote HTML;
- secrets, credentials, or environment values.

Publishing-profile snapshots and public titles are already shared content and
may be listed for oversight. Search in accounts matches username and email;
neither is rendered anywhere a non-operator can see it.

## 7. Account suspension contract

- `users.suspended_at` (datetime) and `users.suspension_reason` (text) are the
  only suspension state.
- Authentication: `Authentication#resume_session` treats a suspended user as
  signed out and destroys the session row; `SessionsController#create` refuses
  a valid password on a suspended account with its own message. Password
  reset requests stay enumeration-safe.
- Suspension is reversible and audited; the operator cannot suspend the
  configured operator account.

## 8. Invitations contract

Backed by the existing `RegistrationInvitation` (digest-only storage,
`issue`, `usable?`, `accept!`). The console adds creation and revocation, the
operator-facing list, and the one-time URL rendering. The sign-up flow is the
ordinary registration flow.

## 9. Jobs API usage

- Read: `SolidQueue::ReadyExecution`, `ScheduledExecution`, `ClaimedExecution`,
  `BlockedExecution`, `FailedExecution`, `Process`, `RecurringTask`, `Pause`,
  and the `SolidQueue::Queue` PORO.
- Write: `FailedExecution#retry`, `Job#discard` (and the class-level
  retry-all/discard-all equivalents), `Queue#pause` / `#resume`.
- The rebuild action writes no queue row directly: it enqueues the
  application's own `Workouts::BackfillRebuildJob`.
- The app adds no gem (no Mission Control), no route mount, and no schema
  changes to the queue database.

## 10. Testing expectations

- Request specs prove 404 for members, sign-in redirect for visitors, and
  operator-only rendering for every route.
- Member HTML never contains an admin link (extends the existing
  information-architecture specs).
- Every mutation has a spec asserting its effect and exactly one `AdminEvent`.
- The jobs panel is tested with real rows in the queue database (connected in
  test by `config/environments/test.rb`); the live fragment is verified in the
  browser, since there is no JavaScript test suite.
- Dashboard and snapshot queries stay bounded (counts and top-N only).
- Privacy negatives mirror `Federation::Diagnostics`: the rendered payload
  must not contain coordinate or secret markers.

## 11. Out of scope

- Multi-operator roles, promotion/demotion, per-account blocks, reports,
  appeals, and moderation case management.
- Trending charts on the dashboard.
- Emailing invitation links; SMTP test sends.
- Account content deletion; suspension does not withdraw publications.
- Browsing users' private workouts or tracks. Impersonation deliberately lives
  outside this console: it is a development-only tool in `devtools/`
  (`AGENTS.md`, "Development tools"), it never ships, and the console neither
  offers nor knows it.
- Any queue `clear` operation.
