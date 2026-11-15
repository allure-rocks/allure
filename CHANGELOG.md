# Changelog

All notable changes to Allure are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

`[devdoc:<topic>]` marks developer documentation that is not published yet; see
[`AGENTS.md`](AGENTS.md).

## [Unreleased]

### Added

- A repository guide (`AGENTS.md`, with `CLAUDE.md` as its alias) and the
  design reference (`docs/dev/DESIGN.md`), so contributors and coding agents
  share the same constraints. A contract whose documentation is not published
  yet is marked `[devdoc:<topic>]` in those files.

## [0.10.0] - 2026-11-13

### Added

- Allure is published on GitHub at <https://github.com/allure-rocks/allure>,
  with a public demo at <https://demo.allure.rocks>, the operator documentation
  at <https://docs.allure.rocks>, and official images `allurerocks/allure` and
  `allurerocks/allure-route-image` on Docker Hub.
- The repository carries the community files: `CONTRIBUTING.md`,
  `CODE_OF_CONDUCT.md`, `SECURITY.md`, issue and pull-request templates, and a
  DCO check on every pull request.
- The initial public snapshot carries the application, the operator
  documentation and the community files; the internal plans, the design
  reference and the runbooks are maintained with the source and are not part of
  this snapshot yet.

### Security

- The federation inbox refusal log drops control characters from the claimed
  actor and the parser's message, so an unauthenticated body can no longer
  forge a log line ([FEDERATION.md](docs/dev/FEDERATION.md)).

### Changed

- Zwift's world map images are committed with their provenance and `© Zwift`
  attribution and ship in the production image; `bin/rails virtual:world_images`
  regenerates them from their pinned sources (`[devdoc:virtual-platforms]`).
- The public demo image is built on the demo host from a release tag and is
  never published by CI, because it carries the third-party FIT corpus
  (`[devdoc:demo]`).
- The About dialog's source link and the operator documentation point at the
  public GitHub repository.
- The CI runs on GitHub Actions: `.github/workflows/ci.yml` verifies every pull
  request and `main`, and `.github/workflows/release.yml` publishes the images,
  the documentation and the GitHub release on a tag.
- The production Compose file pulls the published images by default; the quick
  start is `docker compose pull` instead of a local build.

## [0.9.10] - 2026-11-11

### Added

- A page warns before it drops unsaved changes. Leaving a form that differs
  from what the server saved — a link, a reload, a closed tab, or another form's
  save that would replace the page — asks first, and Back no longer shows an
  unsaved choice as though it had been saved; a form re-rendered after a failed
  save stays marked as unsaved (`DESIGN.md` §14.3).
- A route you record again and again is suggested as one. After three
  recordings of the same complete track, a banner on each activity offers
  « Enregistrer en itinéraire », which opens the route form prefilled from the
  departure and arrival places; « Ignorer » closes the suggestion for good, and
  later repeats join it silently. Nothing is created until you decide, and the
  saved route finds every activity the banner counted ([SEGMENTS.md](docs/dev/SEGMENTS.md)).
- Photos have a manager page of their own at `/workouts/:id/photos`: the route
  as a sticky rail, one row per photo with its caption, capture time, placement
  and the reason an automatic placement found nothing, drag-and-drop ordering
  with keyboard and touch alternatives, and the account's photo quota
  (`DESIGN.md` §20.24).
- An account crops its own avatar. The picker opens a square window over the
  image at its true proportions, with a circular mask showing exactly what the
  avatar will show; dragging, the slider, the wheel, a pinch and the arrow keys
  frame it, and « Recentrer » returns to the centred square. The image is
  covered, never stretched, and uploads up to 20 MB and 8192 px are accepted
  (`DESIGN.md` §9.4).
- A publishing profile can leave sports out of automatic publishing, the way
  it leaves out commutes. The chosen sports' workouts stay unpublished when
  they are imported, and a workout whose sport becomes excluded while it waits
  is skipped; you can still publish them by hand.

### Changed

- The workout photo card is a glance again: the count, « Ajouter des photos »,
  « Gérer », the intake zone and the same square grid readers see, with the
  quota from 80 % of the account's storage. The caption, ordering and placement
  controls moved to the manager, and the lightbox gained « Modifier »
  (`DESIGN.md` §10.22).
- A workout's photos follow their capture time until you reorder them by hand;
  « Trier par heure de prise de vue » restores the automatic order. A
  publication keeps the order it froze.

### Fixed

- A virtual world's map uses the world's dimmed background colour in dark
  mode, so the area around the image no longer stays bright blue.

## [0.9.9] - 2026-11-08

### Added

- A Zwift activity's photos now come with it. The activity detail lists the
  game's snapshots, and the import attaches them through the same pipeline as
  your own uploads — stripped WebP derivatives, the account quota, the
  per-workout cap — so they appear in the workout's gallery and can be placed
  on the map. They carry no EXIF, so they arrive unplaced; the import counts
  the ones it could not fetch or the pipeline refused, and never fails because
  of a photo (`[devdoc:remote-imports]`).

### Changed

- Connected services have their own page beside the settings. The account menu
  opens `/connections`, which lists every service the instance offers with its
  state, the linked account and its last sync; each service has its own page
  with its connection, its retrieval form, its preferences and its unlink
  action. A link or an unlink no longer refreshes — and can no longer wipe —
  another service's form. The former `/settings/connections` address
  redirects, and the notification and batch links open the service's page
  (`[devdoc:remote-imports]`, `DESIGN.md` §8.6).
- A virtual ride now leads with its watts. When a Cycling (Virtual) recording
  carries power, average power takes the place of the speed in the summary
  tiles, on the activity card and as the chart's default secondary line: the
  platform's speed is a game output, the watts are your effort. The elevation
  gain keeps its tile, and the speed stays in the secondary metrics and the
  chart selector (`[devdoc:virtual-platforms]`).
- A virtual ride's map and analysis tables follow its watts too. The colour-by
  selector offers power — first for a virtual ride — and a legend names the
  ramp's two ends; speed and power ramps span the bulk of their readings and
  average each colour stop over its own slice of the route, so a sprint or a
  stop no longer flattens the rest of the ride. The analysis tables read their
  effort column as power with the speed as a quiet second line, and each split
  carries its average power.
- `/me/records` shows one sport at a time. The sport pills (most practised
  first) and a sideways swipe page whole sports, each with its classic records
  and its best efforts side by side on a wide screen; the card takes the shown
  sport's height, so a short sport leaves no blank space under its rows. The
  page opens on your main sport, and the hub's « Voir les records » link opens
  the sport the hub is filtered to (`DESIGN.md` §10.25, §20.8).

### Fixed

- The workout photo card works again. Its viewer is a dark surface in both
  themes with a counter, the capture time and distance, and a link that flies
  the map to the photo's marker; the publish form offers its photo choice only
  when the selected profile shares photos, and says so otherwise. Uploads get a
  translated picker and drop zone, answer size, type and slot refusals before
  sending, and refresh without interrupting an open viewer or a caption being
  typed (`DESIGN.md` §10.22, `[devdoc:photos]`).

## [0.9.8] - 2026-11-07

### Fixed

- A teleport no longer counts as a climb. A video route that returns the rider
  to its start (or any platform jump) splits the recording, but the smart-lap
  climb detector built one elevation profile across the split and counted the
  jump as ascent — a phantom climb of the whole jump, which held the
  biggest-climb record (`[devdoc:virtual-platforms]`). The detector now breaks its
  profile at a boundary whose positions jump 200 m or more; a climb that spans a
  pause stays one climb. A one-off migration rebuilds the laps of the affected
  recordings and recomputes the records.
- A Zwift sync that runs while you are riding no longer imports the activity in
  progress. Zwift lists it from the start, under a provisional name
  (« Zwift - Watopia ») and with a FIT file its uploader is still writing, so
  the import froze a truncated recording that no later sync replaced — the
  listing is deduplicated by external id. The adapter now lists an activity
  only once its declared end has settled (10 minutes), and the next sync takes
  it complete, with its final name (`[devdoc:remote-imports]`).
- A virtual world's map now comes from Zwift's own map CDN, each file pinned by
  its SHA-256 and named after it, so a future update reaches browsers
  immediately (`[devdoc:virtual-platforms]`). Watopia shows the north-west
  archipelago its October 2026 update added, where Tour of Watopia races start,
  and Paris shows its July 2026 expansion — Montmartre, Parc Monceau, the
  Madeleine — on its new, larger frame. The owner route images of activities on
  those two worlds are re-rendered after the upgrade; a published activity
  keeps the image of its publication. Every other world's artwork is unchanged.

## [0.9.7] - 2026-11-07

### Added

- Finding people is an opt-in, minimal name search (`[devdoc:people]`):
  `/people` becomes a tabbed relationship hub (following, followers,
  requests), a live prefix search covers discoverable members and the remote
  accounts you already have a relationship with, and up to five suggestions
  come only from what you can already see — an outing done together, a
  reaction or comment, a shared course — each with its reason and a permanent
  dismissal. `users.discoverable` is `none` for every account by default and
  settable in Settings → Profile; a hidden account remains reachable by its
  exact handle. A followed account can remove an accepted follower, locally
  or with a signed `Reject` for a remote one. A result never carries a
  biography, place, sport or activity, and the follow graph is never
  published.
- Refunds and disputes are recorded as idempotent `funding_reversals` rows
  (kind, outcome, amount, resolved to the original invoice) and shown as
  badges in `/admin/funding`; they never rewrite the original payment nor
  revoke a badge automatically (`[devdoc:funding]`). The Stripe adapter
  normalizes `refund.*` and `charge.dispute.*` events and lists refunds and
  disputes during reconciliation.

### Fixed

- « Synchroniser maintenant » now runs even when automatic sync is off; the
  hourly sweep still only covers connections with automatic sync.
- A virtual platform's teleport — a video route returning to its start, a
  world change — now closes the recording segment instead of drawing a
  straight line across the map and inflating speeds. Existing virtual
  workouts are re-analysed by the workout rebuild (Administration → Jobs, or
  Settings → Data for one account); existing publication snapshots keep
  their frozen value until republished.
- A positionless virtual recording (an indoor Zwift session without GPS) is
  imported again instead of failing during distance calibration.

### Security

- Rails 8.1.4.1 fixes the Active Support, Action Pack, Action View, Active
  Storage and Action Mailbox advisories, including arbitrary file read and
  write in Active Storage image analysis and video previews.

## [0.9.6] - 2026-11-06

### Added

- Import from Withings (`[devdoc:remote-imports]`), off unless the
  operator sets `WITHINGS_IMPORT_ENABLED`. Withings has no public API for
  routes: the integration is unofficial, sends the password once and keeps it
  only while the link task runs, stores only the day-long session, and
  synthesizes a TCX original from the activity's series. A connection imports
  positioned
  sessions only by default — an Apple Health-fed listing is mostly
  auto-detected sessions without a route — with a switch on the card; a
  session that ends leaves the queued batches in place, and « Reconnecter et
  reprendre » resumes them. `bin/rails withings:probe` checks the sign-in
  against a real account.
- Import from Zwift (`[devdoc:remote-imports]`), off unless the operator
  sets `ZWIFT_IMPORT_ENABLED`. Zwift has no public API: the integration is
  unofficial, sends the password once and keeps it only while the link task
  runs, stores only the eight-day refresh token, and imports the original FIT
  file
  of each of the 250 newest activities as virtual cycling or running, with
  its world. `bin/rails zwift:probe` checks the sign-in against a real
  account.
- A virtual world draws its own map (`[devdoc:virtual-platforms]`): a Zwift
  activity's published world image — Watopia, London, Paris and nine other
  worlds — replaces the basemap on the workout page, the route image, a new
  publication's image and a received note, on the world's own background
  colour and with the `© Zwift` credit. The images are Zwift's artwork and are
  not distributed with Allure; an operator generates them for their own
  instance. A world the catalogue does not know, a real-world sport
  and a profile whose `basemap` setting is off keep the ordinary basemap; a
  track that leaves the published bounds still draws on its world's map.

### Changed

- The public demo runs its own image, `demo-latest`, published by CI: the
  application plus the demo seed data and only the FIT files it uses. The
  host no longer needs a checkout of the seeds or the FIT corpus, and the
  nightly reset never changes the deployed version.
- The demo's administration console uses a stable `DEMO_OPERATOR_PASSWORD`
  from the demo env file instead of an unknowable random password, so the
  operator can sign in after the nightly reset. The password is mandatory
  (the demo configures `marie` as operator by default) and is never shown on
  the sign-in page.
- The followers profile is always available. Accepted followers on the
  instance read its publications whatever the federation settings;
  `FEDERATION_RESTRICTED_ENABLED` now only decides whether they also reach
  followers on approved instances, and the profile page says which applies.
  Turning it on does not send the followers publications made while it was
  off. The demo no longer sets it.
- The demo and development seed re-date the dataset near the present — it
  ends yesterday on a fresh database — and date each publication a little
  after its workout, so the feed mixes the accounts. A delayed publication
  whose delay has not run out stays waiting.

### Fixed

- `/people`, following and unfollowing an account of the instance, and
  answering a local follow request work again while `FEDERATION_ENABLED` is
  off; only remote accounts are out of reach.
- FIT recordings from devices that store a GPS position only every few
  seconds (Suunto, COROS) are imported with their route again instead of as
  activities without GPS.
- A virtual activity's elevation is its computed profile, not the platform's
  totals: Zwift writes an ascent with no descent and zero totals in its lap,
  which used to overwrite the profile and show D+ 0 m beside a real
  elevation chart. Existing recordings are re-analysed by the workout
  rebuild (Administration → Jobs, or Settings → Data for one account);
  existing publication snapshots keep their frozen value until they are
  republished.
- A funding subscription records the tier of each paid invoice, not the tier
  of the original checkout, so a plan change records each paid period at the
  tier actually paid.
- A cancellation answered with 404 is terminal only when the subscription is
  proven absent from the account the stored customer belongs to;
  wrong-account or wrong-mode credentials no longer let an account purge
  cancel a subscription that is still charging.
- The demo's database is reported ready only once it accepts connections,
  so the first start after a reset no longer fails.

### Security

- Payment webhook payloads no longer reach the application log: the endpoint
  logs a minimal envelope (event id and type) instead of the full event, and
  the billing keys are filtered as whole subtrees. Signature verification
  still reads the untouched raw body.
- Rack 3.2.8 fixes its security advisories.
- addressable, loofah, nokogiri and rails-html-sanitizer are updated for
  their security advisories.

## [0.9.5] - 2026-10-31

### Added

- Optional whole-history sport totals and personal records on local profiles,
  each with its own audience: nobody (the default), accepted followers, or
  all instance members. Sharing an aggregate does not expose the unpublished
  workouts behind it, their routes or health data, and these blocks never
  federate. Existing enabled preferences retain their member audience.
- A public demo deployment (`[devdoc:demo]`): a shared
  member account, sample workouts re-dated to end yesterday, a nightly
  recreation of the database and storage, and a site-wide reset strip with
  an automatic five-minute warning. Demo mode is off by default and must
  never be enabled on an instance containing real data.
- A settings overview at `/settings`, on desktop and phones, grouping every
  available section in one place.

### Changed

- Local and remote profiles use the publication journal's sport and period
  filters. Optional shared totals appear in paged sport radars with exact
  values and accessible tables; records are paged by sport alongside them.
- The application wordmark is lowercase `allure` with rose punctuation,
  consistently across the application, sign-in and administration headers.

### Fixed

- Renaming a loop no longer loses the rename. A loop the owner renames is
  marked with the rename time (`segments.renamed_at`): the loop reconciliation
  elects it over auto-named duplicates of the same circuit — efforts converge
  onto it instead of away from it — and the orphan sweep never removes it;
  only the owner deletes a renamed loop. The mark is only set by an explicit
  rename, never inferred from a stored name, so a loop renamed before this
  release is protected by renaming it once more.
- EXR FIT downloads initialize the site's session cookies before the first
  download, avoiding an HTTP 500 when only the stored remember cookie exists.
- Smart-lap derivation no longer crashes on a positionless recording whose
  sport supports grade-adjusted pace; its speed intervals use the device's
  measurements without trying to calculate a gradient.
- A late verified funding notification still binds a subscription to an
  account scheduled for deletion, so the purge can cancel its renewal.
  Notifications arriving after deletion has started cancel the renewal
  immediately, without restoring a badge or orphaning a renewing subscription.
- The demo seed can establish local follow relationships while external
  federation remains disabled; remote targets are refused before discovery.

### Security

- Demo startup refuses to publish the operator's credentials. Only configured
  shared accounts receive the public password; background accounts receive
  random passwords. Shared-account security settings cannot change their
  password or enroll a factor, and new demo sessions store no IP address.
- Nightly demo resets explicitly pin the Compose project, directory, env file
  and configuration, preventing an inherited `COMPOSE_PROJECT_NAME` from
  redirecting volume deletion to another stack. Configuration is checked before
  deletion; a host lock and daily success marker prevent overlapping or
  repeated successful resets, and failed or missed runs are retried. Success
  is recorded only once the seeded server passes its healthcheck.
- The demo's real `demo.env` is excluded from Git and the Docker build
  context; deployment instructions require operator-only file permissions.

## [0.9.4] - 2026-10-28

**On upgrade, a one-off migration queues loop reconciliation automatically.**
The queue database must be available during migration. The worker processes
positioned recordings in batches of 100 at backlog priority, including those
already stamped by the previous detector. Existing publications and original
files remain unchanged; progress is visible under Administration → Jobs →
Detected loops. See the [upgrade guide](docs/site/operations/upgrading.md).

### Fixed

- A known owner loop is recognized after a single complete same-direction
  traversal, including after an approach and before a return leg. Discovering
  a new loop still requires two complete laps. Recognition no longer depends
  on new-loop discovery; partial, reversed and recording-gap-spanning
  traversals remain refused.
- Legacy duplicate loops are reconciled in the background, retaining the
  oldest matching loop's identity, name and effort history, rebuilding
  detected laps and removing orphaned duplicates. Previously missed single
  traversals are recovered by the same sweep.

### Changed

- Publication audiences, shared-route eligibility, follow relationships,
  recording windows and recovery conditions now share model scopes instead
  of duplicated SQL, preserving their existing visibility and matching rules.

## [0.9.3] - 2026-10-27

### Added

- Voluntary instance funding (`[devdoc:funding]`), entirely behind the
  `FUNDING_ENABLED` master switch (off by default; while unset nothing renders,
  badges included, and no data is deleted): a « Soutenir l'instance » page
  ("Support this instance") offers a voluntary yearly contribution to the
  operator in three tiers named after the reaction types (`coffee`, `beer`,
  `energy`), an honorific avatar badge (opt-out display, fixed color palette,
  never federated, never in avatar bytes), payment through the provider's
  hosted checkout only (nothing in-app on iOS — `/funding` is hidden from the
  companion), manual granting from `/admin`, and one rolling year per manual
  contribution.
- Stripe annual funding subscriptions: the automated contribution is an
  annually renewing subscription, explicitly disclosed before checkout. One
  immutable contribution is recorded per paid invoice, its billed period
  driving the badge; cancellation stops renewal without revoking the paid
  period, and web-only hosted subscription management is provided. The signed
  webhook, the recovery seam and account-deletion cancellation are
  implemented.
- The pluggable funding provider registry (`Allure::Funding::Providers`),
  normalized `Event`, compact signed `Funding::Reference` and idempotent
  `Funding::RecordContribution` form the provider foundation; Stripe is the
  first registered adapter. HelloAsso automation remains specified.
- The configured operator's avatar carries an operator badge (`DESIGN.md`
  §9.7): a `user-shield` overlay at the lower left, in the brand primary,
  shown whenever `INSTANCE_OPERATOR_USERNAME` is set, beside any supporter
  badge, never federated, never in the avatar bytes.

### Fixed

- Repeated loops are detected after their approach and return legs: a workout
  that rides to a circuit, laps it, and returns home now reuses the detected
  loop segment instead of creating a second one ([SMART-LAPS.md](docs/dev/SMART-LAPS.md)).
- The CSRF state now persists across a cold-start iOS import: the companion's
  first import no longer fails its authenticity check.
- Following a peer again after unblocking its domain restores the
  relationship at once, instead of leaving the two instances unable to
  deliver to each other.

### Security

- crass 1.0.8 (GHSA-pq4g-8rxf-4g29): the CSS tokenizer behind the HTML
  sanitizer that cleans text received from other instances no longer
  mis-tokenizes bad URLs, which could let crafted CSS through.
- Inbox actor fetches are bounded: one at a time per process, metered per
  sender domain, not repeated for an actor that just failed or was just
  fetched, and held to one 8-second deadline including redirects and DNS.
  Inbox requests are also limited to 300 per minute per address.
- A signed read of an outbox, object or media no longer fetches or stores
  an actor this instance does not know (such a signer could only read what
  anonymous readers do), and a known actor's refreshed document is stored
  only once its signature has verified.
- A workout or course from another instance now reaches only the accounts
  that follow its author: naming an account directly no longer puts it in
  that account's feed, and an invitation to confirm taking part is refused
  once the account no longer follows the author.
- Follow acceptance and withdrawal now validate the named relationship, and
  the identity of a follow sent to another instance is no longer guessable.
- Withdrawing or replacing a publication, deleting a comment and deleting
  an account no longer send every instance the full list of the account's
  remote followers and contacts: each instance only sees its own accounts.
- Blocking an instance's domain now also blocks its subdomains and its other
  ports, so a blocked instance cannot come back under another name on the
  same domain; a domain entered with a port still blocks only that address.

## [0.9.2] - 2026-10-25

**Before upgrading, review the reverse proxy and any custom map style.** The
reverse-proxy examples on <https://docs.allure.rocks/install/reverse-proxy>
now allow large bodies (2112 MiB) on the three upload paths only and 32 MiB
everywhere else; Allure itself refuses anything larger. Every page now sends a
Content-Security-Policy: leave it to Allure (a proxy must not add or replace
one), and if a custom `MAP_STYLE_URL` loads tiles, fonts or sprites from other
hosts, list them in `ROUTE_IMAGE_MAP_ORIGINS` (or `CONTENT_SECURITY_POLICY_SOURCES`)
or the map stays blank. The migration (`db:migrate`) is applied on boot.

### Added

- Allure speaks German, Spanish and Dutch: every screen, the development
  tools and the help pages, with the informal address and the privacy wording
  translated faithfully from French and English. The language picker names
  each language in itself.
- The sign-in pages offer a language switcher, and a signed-out visitor is
  served their browser's language when Allure offers it, else English; a new
  account starts in the language it registered in.
- `AUTH_OIDC_REQUIRED_AMR` refuses a generic-provider sign-in whose token's
  `amr` lacks a method (e.g. `mfa`), for providers whose `acr` never varies,
  such as Authentik.
- `CONTENT_SECURITY_POLICY_SOURCES` adds origins the browser may reach under
  the new Content-Security-Policy.

### Changed

- A member may have 3 file imports and 1 Strava archive waiting at a time and
  upload 6 GB in 24 hours; past that the import page says why, and the API
  answers `429 import_limit` with a `reason`. File imports run one at a time
  per account.
- The uploaded files of an import are deleted once it ends — each workout
  keeps its own original — and an import untouched for 7 days is failed and
  its files deleted.
- The import panels refuse files over their size limit before uploading
  them.

### Security

- A Google or OpenID Connect callback carrying a `nonce`, `code_verifier` or
  `redirect_uri` parameter is refused, closing a session-confusion path in
  the provider callback.
- ID tokens signed with the client secret (HS256) or unsigned are refused;
  only asymmetric signatures are accepted, and Google's are pinned to RS256.
- A session started through a provider takes the provider's `auth_time` as
  its proof of identity: a single sign-on session from days ago now asks to
  authenticate again before a sensitive action, and a provider
  re-authentication that reuses an old authentication is refused.
- The CSRF token is rotated at sign-in.
- On an instance with closed registration, a provider identity whose address
  belongs to an account gets the same answer as an unknown one.
- The provider strategy's `/auth/:provider/logout` redirect is no longer
  served.
- Every page sends a Content-Security-Policy: scripts only from this origin
  (the two self-submitting provider pages under a per-request nonce), no
  plugins, no framing by other sites, and network, image and form
  destinations limited to this origin, the map styles' hosts and the enabled
  identity providers.
- Request bodies are limited before Rails reads them: Puma refuses anything
  over 2112 MiB, and each endpoint is held to its own limit (2 GiB archives,
  500 MiB file batches, 32 MiB elsewhere).
- Uploads can no longer fill the disk: the import admission above counts
  every upload's size, both web import forms are rate limited, and the
  uploaded files are released when their import ends, with a daily sweep for
  the rest.
- A ZIP or KMZ declaring more than 10 000 entries (100 000 for a Strava
  archive) is refused before it is opened; a Strava archive keeps at most
  10 000 track files, 20 photos per activity and 20 GB extracted.
- A KML file's `<when>` and `<gx:coord>` elements count against the point
  limit while reading, and the GPX, TCX and KML parsers keep at most 32 sport
  hints.
- Removing GPS spikes takes one pass over a track instead of rescanning it
  after every removal, so a dense zigzag no longer costs hours of analysis.
- The elevation-consistency check compares each sample with at most the 16
  most recent passages of its ground, and loop detection checks a closure
  again only after 5 m of travel and gives up after 200 rejections: a track
  circling the same ground stays linear.
- The account export's CSV files prefix text starting with `=`, `+`, `-` or
  `@` with `'`, so text received from another instance never runs as a
  spreadsheet formula; the JSON files keep every value as it is.
- A database error during an import is no longer shown with its SQL text, and
  a rejected import's log line replaces control characters and line breaks in
  the file name and the parser detail, so an upload cannot forge log lines.

### Fixed

- A file whose track name is over 255 characters or whose description is over
  10 000 is imported with them cut instead of being refused, and an
  over-long device name or lap trigger is cut too.
- A re-sent follow request or a further reaction on a workout no longer makes
  PostgreSQL log a unique-index error.

## [0.9.1] - 2026-10-22

### Changed

- The heart-rate zones statistics page uses the same controls as Me: sport
  pills with each sport's workouts with heart rate and a « Semaines » /
  « Mois » switch, two native selects on phones, and the hours / share choice
  in the chart card's header. The low / moderate / high split reads as a
  figure strip, and on phones the period table becomes a list, each period
  with its total, a zone bar and its five values.
- On phones, the Segments list keeps « Nouveau » and « Découvrir » beside the
  title, like a workout page, and its Segments / Itinéraires / Boucles switch
  is larger and spans the width.

### Fixed

- On phones, dialogs (About, release notes, confirmations) keep clear of the
  notch, the iOS companion's tab bar and the home indicator, and a header
  whose title wraps no longer touches the dialog's edge. The feedback button
  no longer covers an open dialog.
- The records page scrolls freely on phones: its tables no longer catch the
  swipe.
- The heart-rate zones page's empty state no longer touches the privacy line
  below it.

## [0.9.0] - 2026-10-21

**Before upgrading a production instance, rescue its files.** Earlier
`docker-compose.production.yml` files mounted the storage volume where the
application never wrote, so uploaded originals, photos and route images live
inside the running containers. Stop the stack with `stop` (never `down`), copy
`/rails/storage` out of the `rails`, `worker` and `route-image-worker`
containers into the volume, then start the new release: the steps are in
“Upgrading” on <https://docs.allure.rocks/operations/upgrading>. Run the
migration (`db:migrate`, applied on boot).

### Added

- Import a Strava archive (`[devdoc:strava-archive]`): a new « Archive Strava »
  tab on the import page takes the ZIP Strava sends (up to 2 GB) and imports
  each activity's original file with its Strava name, type, description,
  private note, commute flag and gear, in any Strava language. Missing gear is
  created, and activities typed in by hand on Strava become manual entries,
  their date read in any of eight languages. The archive's photos are
  attached, private, to the activities they belong to, within the account's
  photo storage. The account is mailed when its archive is imported, with the
  counts, or why it failed. Re-importing an archive, or one whose rides were
  already imported from Garmin Connect, creates no duplicate. The REST API
  takes an archive too: `POST /imports` with `source=strava_archive`.
- Help for members: an « Aide » entry in the account menu — the iOS
  companion's too — opens five short pages on the ideas behind the screens:
  publishing, privacy zones, sharing beyond the instance, segments and
  leaderboards, training load. The screens they explain link to them with
  « En savoir plus ».
- An About dialog, from the account menu (the companion's too) and the
  footer: the instance and its operator, the outside services it is set to
  use and what reaches them, the source of the running code and the credits.
  `ALLURE_SOURCE_URL` points the source link at your own repository when you
  run a modified version (the upstream repository otherwise), as the AGPL
  asks.
- Operator documentation at <https://docs.allure.rocks>: installation,
  configuration and every environment variable, the optional features,
  upgrading, backups and restore, background jobs, the administration
  console, monitoring, troubleshooting and the CLI tasks. The repository now
  carries its `LICENSE` (AGPL-3.0-or-later).

### Changed

- A bulk import — a Strava archive, a file batch of more than five entries,
  a date-range retrieval — enriches its activities behind new outings: their
  route images, places, segment matching, weather and photos run at a lower
  job priority, so a ride uploaded meanwhile is not stuck for hours behind
  someone's history.
- The privacy-zones pages state in full what a zone does and does not do, on
  the list and in the editor.
- The production Compose file reads `INSTANCE_OPERATOR_USERNAME`, the
  `INSTANCE_*` presentation variables, the geocoding tuning variables,
  `ALLOW_REGISTRATION`, `FEDERATION_ENABLED` and
  `FEDERATION_RESTRICTED_ENABLED` from `.env.production` (registration and
  federation still off unless set): no Compose override is needed for them
  any more.
- The reference Grafana dashboard (`docs/grafana/allure.json`) is in English,
  like the operator documentation; re-import it to update yours.

### Fixed

- **The production storage volume is mounted where the application writes**
  (`/rails/storage`, not `/app/storage`): files are shared between the web
  and worker containers and survive a container's recreation. See the note
  above before upgrading.
- The production image carries the OpenAPI document, so
  `/api/rest/v1/openapi.json`, `.yaml` and the API reference at
  `/developers/api` answer instead of failing.
- The production web container joins the `egress` network: sign-in through
  an identity provider, the privacy-zone place search and federation's inbox
  call out during a request and failed on the stock stack.
- The operator console could not be reached on the stock stack, which did not
  pass `INSTANCE_OPERATOR_USERNAME` to the containers.
- An import interrupted by a restart no longer reports the activity it was
  importing as a duplicate of itself: the entry takes its workout back, and a
  Strava archive attaches its photos then.

## [0.8.7] - 2026-10-20

### Changed

- Heart-rate coverage is read against the time the device recorded, pauses
  excluded (`[devdoc:heart-rate]`, histogram version 2): a paused timer no
  longer reads as a lost strap. Values a losing strap held are left out of the
  zones and the load, and a recording whose points are minutes apart is named
  « trop espacé » instead of being sliced. Run the heart-rate sweep from
  `/admin/jobs` (or `bin/rails workouts:heart_rate`) after deploying.
- The training load follows Edwards' method to the letter: time under the
  load floor (50 % of the maximum with the default thresholds) stays in zone 1
  but carries no load. Every stored load is read again from its histogram.
- The proposed maximum heart rate is the highest one a recording held at least
  10 seconds, never a single spike, and is presented as a floor.
- The training-load table groups the days by the account's calendar week and
  marks the unfinished one.

### Added

- Explanations of the heart-rate features: what the training-load points are
  (Allure's own unit, compared with nothing else), how to read fitness,
  fatigue and form, the six-week warm-up shaded on the chart, the sessions
  with partial heart rate, the session's load and the basis of the zones in
  the « Zones cardiaques » tab, the reason a recording has no zones, a live
  preview and one-line descriptions of the zones in the settings, and a
  hours / distribution switch with a low / moderate / high reading on the
  statistics page.
- `heart_rate.covered_seconds`, `frozen_seconds` and `load_floor_bpm` in the
  REST workout detail.
- Inbox refusals are logged with their reason and the claimed actor, and
  counted in `allure_federation_inbox_refusals_total{reason}`.
- Blocking a domain cancels the deliveries still waiting for it, which makes
  it the way to let an instance that disappeared go.
- `bin/rails federation:repair_relationships` (dry run unless `APPLY=1`) ends
  the follows left with blocked or deleted accounts before this release. Run
  it once after deploying.
- `bin/rails federation:rename_host FROM=<old base URL>` (dry run unless
  `APPLY=1`) moves the stored local identities to a new
  `FEDERATION_BASE_URL`; an actor created under another base URL now names
  this task instead of failing with a bare identity conflict.

### Fixed

- A follower whose instance did not answer at the moment a publication was
  sent was dropped for good; the cached account is now kept and the delivery
  retried like any other.
- Inbound signatures are checked with the key already known, however old, and
  the account is fetched again only when that key does not verify. A peer that
  was reset with new keys is recognised at once, a slow peer no longer gets
  its activities refused, and an account deleted on its instance can still
  deliver its deletion. When the sender's account cannot be fetched right now
  the inbox answers 503 with `Retry-After` instead of 401, and outgoing
  deliveries retry a 401 as Mastodon does.
- A deletion of an unknown account by itself is acknowledged without fetching
  or storing anything.
- A Reject of an accepted follow, which Mastodon sends when its owner removes
  a follower, now ends the relationship and withdraws what it delivered.
- Asking again after a refusal stayed refused: the follow now returns to
  pending, so the answer is taken into account.
- Blocking an account or a domain, and the deletion of a remote account, now
  end the follows with it in both directions; `/people` no longer lists them.
- Inbound activities whose processing was lost or interrupted are picked up
  again by the recovery job.
- A signed delivery no longer follows a redirect its signature cannot
  survive; it fails with that reason.

## [0.8.6] - 2026-10-20

### Fixed

- Unfollowing a remote account no longer needs its instance to answer: the
  relationship is found by the stored actor (URI, acct or handle) and undone
  locally, so an instance that disappeared or changed domain, or an author it
  deleted, can still be unfollowed. It used to fail with a server error.
- Following an account on an unreachable instance shows an alert instead of a
  server error page.
- A follower asking again under a new Follow, because its unfollow never
  reached this instance (after a domain change or an outage), is accepted
  again at once instead of waiting forever; the relationship takes the new
  Follow id so a later unfollow is heard.
- The notification count badge stays pinned on the bell's corner.

## [0.8.5] - 2026-10-20

### Added

- Heart-rate zones (`[devdoc:heart-rate]`). An account sets its maximum and
  optional resting heart rate, the zone basis (percent of the maximum, or of
  the reserve after Karvonen) and the lower bounds of zones 2 to 5 at
  `/settings/heart-rate`, which proposes the highest observed maximum the
  anomaly pass did not contest. Every recording holding heart rate gets a
  seconds-per-bpm histogram (`workout_heart_rates`), computed at import and
  re-analysis and swept for existing workouts from `/admin/jobs`,
  `/settings/data` or `bin/rails workouts:heart_rate`; changing the profile
  re-slices the zones without reading a point.
- The workout's analysis card gains a « Zones cardiaques » tab: a stacked bar
  and a table of the time in each zone, with the share of the session that
  carried a heart rate when it falls under 95 %. Hovering or pinning a zone
  shades every stretch ridden in it on the profile and the map.
- A « Charge d'entraînement » card on `/me`: fitness, fatigue and form from
  the Edwards load of every sport over the last 90 days (42- and 7-day
  weighted averages), with the sessions left out for lack of heart rate.
- `/me/stats/heart_rate` stacks the time in each zone per week or month, for
  every sport or one.
- The REST API carries `heart_rate` on a workout's detail and
  `heart_rate_profile` on `/me`; the account export carries the profile.
  Nothing derived from heart rate is ever published or federated.
- Courses take their elevation from the terrain service by default when the
  instance configures one (`[devdoc:elevation]`): a public course with the
  service alone, a private or followers-only one with its owner's consent. The
  course's ascent, descent, grade and profile are recomputed once from its own
  line, the chart carries the « Altitudes estimées (MNT) » badge, and
  `/admin/jobs` (or `bin/rails segments:terrain_elevation`) applies it to
  existing courses. Existing publications do not change.

### Changed

- A course's average grade is signed: the net change from start to finish
  over its distance, so a descent reads negative instead of 0 %. Existing
  courses are recomputed from their stored profile.
- A course that mostly descends leads with its descent, on its page and in
  the segment list, whose « Dénivelé » column sorts by the leading figure and
  whose grade sorts by steepness.
- An effort on a reusable segment shows the course's ascent and descent in the
  workout's « Segments » tab, one reference for every athlete.
- New publishing profiles no longer share average and maximum heart rate:
  heart rate is health data, and the form groups the metrics with a sentence
  saying so. Existing profiles keep their choice.

## [0.8.4] - 2026-10-19

### Added

- A populated reaction pill's tooltip names who reacted: the newest three
  accounts per type, then « et N autres personnes », the viewer as « Vous »
  leading the list, and the owner reading the gesture addressed to their
  activity (« Éric a trinqué à votre activité »). A deleted, blocked or
  deactivated account is never named but still counts. Names follow the
  audience: a reaction records the audience it was given through
  (`reactions.audience`), counts stay global, and a reactor is named only to
  the readers of that audience, so a follower's reaction never names them to a
  reader of the public version; when nobody can be named, the sentence counts
  people. Existing reactions are classified fail-closed by the migration
  ([REACTIONS.md](docs/dev/REACTIONS.md)). The REST API keeps `counts` and `mine`.

### Changed

- Recording devices are named from the FIT SDK 21.218.0 manufacturer list and
  its Garmin product codes (`Allure::Fit::Devices`) instead of a hand-written
  table that named nine of its 27 brands wrong and lacked iGPSPORT, whose
  computers showed no device at all. The creator names the model from its code
  before falling back to the brand. Import detection moves to version 3: the
  rebuild on `/admin/jobs` fills an empty device or replaces a name the old
  table derived, and keeps any other stored value.

### Fixed

- Segment matching no longer deadlocks when a backfill matches many workouts
  against the same segments: refreshes run after the matching commit, in id
  order, each behind a lock on its segment row; one match runs at a time per
  account; and a segment deleted meanwhile is skipped instead of discarding
  the job.
- The production image carries the weather icons, which 0.8.3 shipped
  without: they move from `app/frontend/icons/weather`, which only Vite
  reads, to `app/views/weather/icons`, server-owned like the sport icons.
  The profile and map markers receive their icon from the server, so the
  icons also leave the JavaScript bundle every page loaded (about 19 kB
  gzipped).
- A shared course's participant count no longer reveals athletes the reader
  cannot see: the course page's Participants tile and the `Découvrir` popup
  count the distinct athletes of the reader's own board, like `Mon rang`, so
  an unpublished, opted-out or zoned effort no longer shows through. A private
  course still counts every recorded effort for its owner.

### Security

- The feed hides a deactivated account's publications: the following stream's
  raw union now applies the deletion-window rule
  (`WorkoutPublication.of_available_owners`) like every other local surface
  (`[devdoc:account]`).
- A due scheduled publication waits out its owner's deletion window instead of
  activating behind it: the publication policy refuses a deactivated owner's
  deliveries, so it would have gone live without reaching anyone. The recovery
  sweep activates it once the window is cancelled; the purge cancels it with
  its workout.
- A confirmed cancellation stops a purge that had already read the schedule:
  the cut-off re-checks it under the row lock and raises
  `Users::DeleteAccount::Cancelled`, which the purge job swallows
  (`[devdoc:account]`).
- Push subscription secrets are filtered from the logs (`[devdoc:push]`).
- A push registration replaces only the current account's earlier row for
  the same endpoint, and only when the new subscription saves: an endpoint
  is never proof of ownership, so another account's row is left alone (422),
  and an invalid registration no longer unbinds the row it names.
- An inbound activity's `id` must live on its actor's authority, the binding
  `Create` and `Delete` already apply to their objects. An activity admitted
  under a URI a peer's future `Delete` or `Follow` would carry could suppress
  that withdrawal or block that follow; `Federation::Parsers::Activity` now
  refuses such an activity before any row is written ([FEDERATION.md](docs/dev/FEDERATION.md)).
- A suspended account, or one inside its deletion window, is no longer named
  under its comments: the card shows « Un compte indisponible » with a
  neutral avatar and no handle or link, and the REST comment's `author` is
  null, until reinstatement ([COMMENTS.md](docs/dev/COMMENTS.md)).

## [0.8.3] - 2026-10-18

### Added

- Elevation that disagrees with itself is flagged (analysis version 13,
  `Allure::Gpx::ElevationConsistency`): where a route passes the same ground
  twice, at least 300 m and 300 s apart, a gap of 10 m or more holding over
  200 m becomes an `elevation_mismatch` finding in « Qualité des données ».
  A gap reaching 15 m and a tenth of the ascent contests the ascent, which
  then never wins the `HA` record; the D+ and D− tiles carry the warning
  beside their label, and the tab offers the terrain profile where the
  instance and the account allow it. Existing workouts are checked through
  the rebuild on `/admin/jobs`.
- The comment thread of a publication has its own page
  (`/workouts/:id/comments`, `/remote_notes/:id/comments`), serving exactly
  the readers the card serves. On phones the workout and received-note pages
  replace the comments card with a social row under the summary — the
  thread's button on the left, the reactions on the right — and the feed
  pill, the comment notifications and the no-JavaScript fallback open the
  page.

### Changed

- Weather icons are **Meteocons** (Bas Milius, MIT, vendored in
  `app/frontend/icons/weather` with their LICENSE) instead of Tabler glyphs:
  the monochrome style in the theme's primary (white on the profile and map
  pills), animated — static in the hourly table and under
  `prefers-reduced-motion`. Every condition that has a night variant shows
  it, decided by the sun's elevation at the sample's own hour and place, so
  the provider is asked nothing extra; the summary carries `is_day` (a
  `weather_day` Note tag) and the hourly rows `day`. The weather enricher's
  analysis version 3 converges existing weather offline.
- Creating a segment or a route from the Segments page: « Nouveau segment »
  and « Nouvel itinéraire » open a « Choisir une activité » step that leads
  with the latest activity and lists the others with a place search, instead
  of sending the owner to the workout list. The Loops tab no longer shows a
  create action.
- The Découvrir map tells stacked courses apart: courses sharing a stretch
  of road take nuances of the primary, the shorter drawn on top, each with
  its direction on the line itself; a hover bubble names every course under
  the pointer and a click pins it with their links. The map follows the
  account's units, collapses its attribution, uses cooperative gestures on
  touch screens and gains a « Liste » action.
- Every interactive map's basemap — workout, segment, Découvrir,
  privacy-zone picker — follows the account preference « Fond des cartes et
  images des parcours »: `auto` follows the page, `light` and `dark` force a
  style, and the map's controls, markers and popups follow the basemap.
- The reactions leave the workout and received-note headers for the social
  row under the summary, on every screen.

### Fixed

- The header weather badge no longer stands taller than the badges beside
  it.
- The Découvrir popup takes the inverted floating surface instead of the
  page's own, which read black on the dark theme.

## [0.8.2] - 2026-10-18

### Added

- Historical weather along outdoor workouts (`[devdoc:weather]`), from
  Open-Meteo.
  - **Opt-in:** offered while `WEATHER_ENABLED` is set (with optional
    `WEATHER_*` tuning, see `.env.example`), and fetched only for an account
    that turns it on at `/settings/weather` — off for everyone. Positions
    leave rounded to 0.1° (about 11 km) with their recorded elevation.
    Withdrawing consent stops every request; the weather already fetched
    stays until the owner deletes it there.
  - **Workout page:** a header badge (condition and mean temperature); a
    weather card after the analysis (conditions, temperatures, apparent
    temperature, wind and gusts, humidity, precipitation, the head / cross /
    tail wind share); a « Météo » analysis tab whose markers show each change
    of weather on the profile and the map; a wind column on the splits; and
    the temperature and headwind as profile series.
  - **Sharing:** a publishing profile's « Météo » setting (off by default)
    publishes the summary, never the hourly weather. It travels as
    `weather_*` Note tags that other Allure instances parse and display, and
    the feed card carries the same badge.
  - **Programs and operations:** the REST workout carries `weather`; the
    operator schedules an audited backfill from `/admin/jobs`, an account
    from `/settings/data`; `/metrics` exports `allure_workout_weathers` and
    `allure_weather_requests_total`.
- The device's own air temperature (FIT `record.temperature`, GPX `atemp`) is
  kept on every point and shown to the owner on the weather card and as a
  profile series. Analysis version 12: existing workouts gain it through the
  rebuild on `/admin/jobs`.

### Fixed

- A route endpoint is named after the settlement it actually ends in: when
  Nominatim answers with a way-side dwelling while the recording stops in
  the village core, the closest settlement centre now wins (toponymy
  algorithm 9). The `/admin/jobs` sweep re-derives existing places offline
  from the stored samples, asking only the endpoint settlements' centres.

## [0.8.1] - 2026-10-18

### Added

- Manual entries (`[devdoc:manual-entry]`): a « Saisie manuelle » tab on the
  import page records a workout typed in by hand — no file, no position, only
  the typed figures (`origin: "manual"`). It counts in totals, statistics and
  equipment wear, never in records, and cannot be published. The REST API
  creates one with `POST /api/rest/v1/workouts` and edits it through `PATCH`.
- Data export and account deletion (`[devdoc:account]`), on
  `/settings/account`.
  - **Export:** one ZIP built in the background with the original files (in
    nested archives the import page reads back), the workouts as JSON and
    CSV, records, segments, equipment, publishing profiles, privacy zones,
    publication snapshots, Mastodon-format follows, comments, reactions and
    sessions, and no secret. One at a time and one per day, kept seven days,
    downloadable by its owner only; a notification and a mail announce it.
  - **Deletion:** the account is deactivated for seven days — every page
    leads to the cancellation page, its publications and courses are hidden,
    nothing runs or federates on its behalf, API tokens are refused — then an
    hourly sweep withdraws the actor and purges the account. A deleted
    username is never handed out again. The operator schedules or cancels
    another account's deletion from `/admin/accounts`, audited.
  - `/metrics` exports `allure_account_exports` and
    `allure_account_deletions_scheduled`.
- Leaderboard categories ([SEGMENTS.md](docs/dev/SEGMENTS.md)): an account may declare
  a category (women, men, or unspecified by default) at `/settings/profile`.
  The full board gains a Tous / Femmes / Hommes view over the ranking the
  reader already sees, offered per sport from three athletes of that
  category, and « Mon rang » adds the category place. The category never
  leaves the boards.
- A place search in the privacy-zone editor: one explicit Nominatim request
  per search through the instance's geocoding provider, rate limited and kept
  out of the logs; picking a result moves the marker and the map.

### Changed

- Privacy zones are listed in the same compact table as the publishing
  profiles.
- More usernames are reserved for new accounts: account and role words,
  brand variants, audience words, infrastructure names, every first segment
  of the application's routes, and the configured `INSTANCE_NAME` at
  self-registration. Existing accounts keep their name; the sign-up and
  onboarding forms say some names are reserved.
- One import surface: the former single-file workout form (`/workouts/new`)
  merged into the import page (`/workout_imports/new`), and the old address
  redirects there. The import page's options card now carries the fallback
  sport, the equipment and the commute flag (applied to every imported
  workout), the notes, and a title offered when a single file is selected.
  The page and its progress view drop the "batch" wording.

### Fixed

- The selection popup of the intensity pulse and the activity calendar on
  `/me` wears the same inverted surface as every other tooltip — dark on the
  light theme, light on the dark one — instead of the page's own surface,
  which read as the opposite popup in both themes. Its facts line and its
  controls are inked for that surface.
- A deleted account's username could be claimed again at sign-up; only the
  withdrawn actor reserves it now, as [FEDERATION.md](docs/dev/FEDERATION.md) requires.

## [0.8.0] - 2026-10-17

### Added

- A reference Grafana dashboard for the Prometheus exporter,
  `docs/grafana/allure.json` (« Allure — Instance », `[devdoc:metrics]`).
  Import it through Grafana's *Dashboards → Import*; it is documentation, not
  provisioned by the application, and carries no alert. Its rows cover
  instance health, HTTP, background jobs, federation, usage, and imports and
  connections.

### Changed

- Every chart is drawn by Apache ECharts instead of ApexCharts. The profile,
  the course progression, the intensity pulse, the sport mix and the statistics
  keep their behaviour:
  map ↔ profile hover, zoom by mouse drag or touch long-press, the course
  selection, the anomaly dashes, live light/dark theme.
  - **Lighter pages:** the chart library is loaded only by a page that draws
    a chart. The main script drops from 440 kB to 177 kB gzipped; the first
    chart fetches 245 kB.
  - **Sport mix:** the legend is a list of buttons, reachable from the
    keyboard, each with its share.
  - **Statistics:** the per-sport chart is horizontal bars, as `DESIGN.md`
    §15.1 asks, with a translated unit; both statistics charts follow a theme
    change.
  - **Profile:** a place's or pictogram's name shows in the reading tooltip
    when the pointer is on it. A theme change resets the zoom.
- Runtime and dependencies: Ruby 4.0.7 and Node 24 LTS in the production,
  development and CI images, Rails 8.1.4, and minor and patch updates of the
  gems and npm packages (MapLibre 6.14, Vite 8.3, Tabler icons 3.49, Scalar
  1.75), which clear every `npm audit` finding. Operators rebuild their images
  as for any release.
- Metrics: jobs on the `webhooks` queue are reported under
  `queue="webhooks"` instead of `queue="other"` in the `allure_jobs_*`
  families.

### Fixed

- Creating a segment: the start and end points typed in the form now draw
  the selected band on the profile. They usually drew nothing, because the
  profile shows at most 1,000 points and a typed index rarely matched one
  exactly; the nearest plotted point is used now.

## [0.7.3] - 2026-10-17

### Added

- Shared activities across instances (`[devdoc:shared-activities]`): a
  workout owner can invite an account on another Allure instance
  (`@nom@instance`) to confirm they did the outing together.
  - **Who can be invited:** the account must follow the owner and have
    received the workout's publication, and that publication must share
    distance, duration, moving time, ascent, descent and average speed.
  - **On the wire:** the invitation travels as an ActivityStreams `Invite`
    addressed to that account alone. It rides on the publication: it waits
    for it, goes nowhere it did not go, and stops when the publication is
    withdrawn. It carries no figure and no geometry.
  - **On the invited account's side:** an « Activité partagée » card on the
    received note offers Confirmer / Refuser, then Retirer. The answers go
    back as `Accept`, `Reject` and `Undo`; a refusal is final.
  - **The credit row:** a confirmation adds the outing to the account's
    activities, built from the note's figures. It counts in statistics and
    records, with no best efforts or segments, and its map and image are the
    received note's.
  - **How it ends:** a withdrawal by either side, an unfollow or a block. If
    the publication is deleted or republished, the credit is kept, and an
    invitation for the republished outing re-attaches it.
- `GEOCODING_REQUESTS_PER_SECOND` (default `10`) and `GEOCODING_CONCURRENCY`
  (default `1`) let an instance that operates its own geocoding provider
  raise the instance-wide request budget and run several geocoding jobs at
  once. Each job paces itself to its share of the budget.

### Changed

- A workout's participants share one « Avec » badge that links nowhere on
  the owner's side. Two names are printed; from three on, the first and a
  count (« Avec Eva et 2 autres »), with the tooltip naming everyone. The
  badge still opens the source when it names a single linked source.
- Webhooks: `participation.requested` and `participation.confirmed` carry
  `remote_note_id` instead of `workout_id` for an invitation received from
  another instance; `workout_id` is no longer required in
  `ParticipationData`.
- Push: the relay binds every endpoint to the instance's VAPID public key
  (`[devdoc:push]`), so a leaked endpoint cannot be used without the
  instance's private key. The « Sur cet iPhone » card hands the key to the
  app when it registers. Instances that enabled push in 0.7.2 must upgrade
  before the iOS app with push ships: the relay refuses registrations without
  the key. Changing the VAPID pair now cuts every device off: the relay
  answers `403 key_mismatch`, the subscription is deleted, and the card
  registers the device again on the account's next visit, without asking
  for permission.

### Fixed

- Resetting a forgotten password works again. The form's new password was
  never read, so every reset saved nothing, closed the account's sessions,
  and still announced a changed password.
- A webhook that fails to build no longer costs the in-app notification of
  the same event.
- Federation ring gate (`dip fed_test`, development only): the signed-in
  phases had failed since the second factor shipped, because the runner's
  execution context was lost after the first request.

## [0.7.2] - 2026-10-16

### Added

- Push notifications for the iOS companion (`[devdoc:push]`, instance side):
  an account turns on « Recevoir sur cet iPhone » in the new « Sur cet
  iPhone » card of `/settings/notifications`, optionally hiding the content,
  and every new notification it would see in the inbox is also pushed to that
  device. Payloads are standard Web Push, encrypted for the device (RFC 8291)
  and signed for the relay (VAPID), and reach APNs through the publisher's
  relay (`https://push.allure.rocks`), which only sees an opaque blob. A
  subscription belongs to its session, so signing out, expiry or closing the
  session from Security removes it; a gone endpoint or ten failures in a row
  delete it. `/metrics` exports `allure_push_deliveries_total{result}` and
  `allure_push_subscriptions`. Push is off until `VAPID_PUBLIC_KEY`,
  `VAPID_PRIVATE_KEY` and `VAPID_SUBJECT` are all set — generate the pair
  with `bin/rails push:vapid_keys`; `PUSH_RELAY_ORIGINS` lists the accepted
  relays.
- An invitation can carry a display name (`/admin/invitations`, or
  `NAME=` for `bin/rails users:invite`): it prefills the sign-up form and the
  provider onboarding, and the invitee may change it. The password sign-up
  form now asks for a display name too, so a new account no longer shows only
  its username.

### Changed

- Reactions on one workout share a single notification: « Marie et 59 autres
  personnes ont réagi… » names the newest account, counts the others, turns
  unread again on a new reaction, and is recounted rather than deleted when a
  reaction is withdrawn or its author blocked or deleted. Existing reaction
  notifications are folded into one per workout by the migration. The
  `reaction.created` webhook still fires once per reaction.
- The inbox cap no longer prunes unread notifications that await a decision
  or a repair, so a burst of reactions cannot erase a pending follow request.

### Fixed

- The workout page no longer slides sideways on touch: a long unbroken token —
  a pasted address in a title, a device name without spaces — wraps instead of
  widening the page, the description and its notes wrap too, and the page
  itself never turns a stray overflow into a horizontal scroll.

## [0.7.1] - 2026-10-15

### Added

- An activity file that records no position at all is imported instead of
  being rejected (`[devdoc:no-gps]`): a trainer ride, a treadmill run, an erg
  session, a pool swim or a duration-only session takes its distance, duration
  and pace from the device's own records rather than from GPS, and its page
  drops the map for the « Sans position GPS » state. It has no route to share,
  so publishing is refused, and every geography-driven derivation — venue,
  route image, segment matching, co-presence, terrain elevation, toponymy —
  is skipped.
- Two duration-only sports join the catalogue and the sport picker:
  « Renforcement musculaire » (`strength_training`) and « Fitness »
  (`fitness`, the catch-all a bare FIT `fitness_equipment` session resolves to).

### Changed

- Every sport icon now lives on the same 1000×1000 grid and draws at the same
  60-unit stroke: twelve are redrawn by hand — the six cycling variants, the
  electric mountain bike, running, trail, hiking, walking and pool swimming —
  and the Tabler-derived ones, with the Font Awesome and SVG Repo
  silhouettes, are converted coordinate by coordinate. The mountain bike takes
  the electric one's drawing without its bolt, virtual running Tabler's
  treadmill in place of the filled runner, and swimrun the open-water swimmer
  itself. Windsurfing trades its filled picture for a drawn sail, boom and
  board, and rowing its filled blades for two oars drawn at the set's stroke.
- The sport glyph is sized to the surface that shows it: the hub's recent
  segments table draws it at the row's text size, and the sport pills of the
  hub, the workout list and the segments list raise it to 1.25em.
- The production image no longer carries the development demo seed: its
  loader and fixtures are excluded by `.dockerignore`, so `db:seed` in
  production seeds the reference catalogs alone.
- Development only: the operator can act as any seeded account from the
  account menu's « Agir en tant que… » (`devtools/`, never shipped in the
  production image).
- Every sharing state is one badge: the broadcast mark in its tint — green for
  public, blue for followers, the same tint with a slow pulse while a
  publication waits out its delay, grey with the cut mark when nothing is
  published — wherever a workout's or a course's publication state is read:
  the workout page, the cards, the list and its table, the feed, the sharing
  card, a course's row, its page and the reach line of its board, a followers
  comment and the administration console.
  The per-audience and per-state glyphs (`ti-world`, `ti-users`, `ti-clock`,
  `ti-eye-off`) are retired, and the pulse is dropped under
  `prefers-reduced-motion`.
- The viewer's own items and the activities done with someone take the same
  state badge: « À moi » on a course of theirs and « Vous » on their own
  publication in the feed show the user circle in the primary tint; « Avec @X »
  shows `ti-users` in the primary tint, links to the source, turns grey once
  the source is deleted, and now also sits, icon-only, on the cards of a credit
  row and of a recording linked to someone's outing. The source's owner now
  reads it too: one « Avec @X » per confirmed participant on the workout's
  header and card, linking to their profile.
- A state badge prints its label from `md` up and only hides it visually
  below, where it falls back to the square icon pill and a tooltip gated on the
  same media query names the state; the workout cards and the phone rows of a
  list keep the icon-only form at every width. The tooltip controller follows
  that query, and takes its focus stop with it, so a printed label never
  carries a redundant tooltip.

### Fixed

- Long climbs and descents are detected again: the climb segmenter capped a
  climb at 10 km, so a steady alpine climb with no dip on the way — the Alpe
  d'Huez, 14 km — vanished from the « Montées » tab, the chart and the
  geocoded summits, and its descent came out in pieces. The cap is now 30 km,
  a climb never reaches back past a point higher than its summit, and two
  overlapping climbs keep only the stronger ([SMART-LAPS.md](docs/dev/SMART-LAPS.md)).
  `Laps::Rebuild::VERSION` moves to 5 and
  `Workouts::ToponymyEnricher::ALGORITHM_VERSION` to 8. After deploying, run
  the toponymy backfill from `/admin/jobs` (which re-geocodes, at the
  provider's throttled rate) and then `bin/rails laps:backfill` to rebuild the
  detected laps and the biggest-climb records.
- The « Sorties faites ensemble » backfill card on `/admin/jobs` shows even
  when no geocoding provider is configured.

## [0.7.0] - 2026-10-14

### Added

- A confirmed credit counts for the participant (`[devdoc:shared-activities]`):
  it gives them a **credit row**, an activity of their own holding only the
  credited metrics — distance, durations, ascent and descent, speeds, paces,
  title — and no track, file, heart rate, cadence, power, calories, device
  or places, enforced by check constraints. It counts in every statistic,
  `/me`, the column records, best efforts, personal segment bests and the
  biggest-climb record (`credited_max_climb`), all derived from the
  source's points for the participant. It follows the source's edits,
  re-analyses and sport changes; withdrawal and conversion remove it.
- The credit row page shows the credited metrics, the « Avec @X » badge to
  the source, the participant's Segments and « Meilleurs efforts » tabs, and
  the source's map and card image read through the publication the
  participant may read, never the raw track. It is read-only except for
  « Retirer de mes activités ».
- Deleting a source, or its owner's account, keeps the participants' credit
  rows as frozen metrics-only activities without the owner's title, with the
  new `participation_source_deleted` notice; a credit later confirmed for the
  same owner's re-imported activity re-attaches the kept row.
- Links have their interface: the confirm card offers the participant's own
  recordings starting within six hours of the source, a confirmed credit
  converts later (« Lier mon enregistrement »), and a link shows on both
  workouts.
- Outings done together are detected (`[devdoc:shared-activities]`): after each
  import, `Allure::Together::Detector` compares the recording with those of
  local accounts following each other in both directions — same sport
  family, overlapping windows, both within 60 m at least 80 % of the shared
  time — and suggests a link that both accounts confirm from their own
  workout (`participation_suggested`). A suggestion shows no place, distance
  or score, and the other account's workout stays closed until both
  confirmed. Each account can turn detection off in the notification
  settings; existing workouts are compared through the audited « Sorties
  faites ensemble » action on `/admin/jobs`.
- A credited participant's own recording of the same outing is detected too
  and suggested as a link (`participation_link_suggested`, a banner on the
  recording and the credit row), until they link it or dismiss it.
- REST, webhooks and MCP name a credited workout: `origin` (`import` or
  `credit`) and `credit` (`recorded_by`, `source_deleted`); creating a credit
  row emits `workout.created`, and the `credited_workout` problem refuses
  changing or publishing one.
- A development demo dataset built from the optional FIT corpus: ten
  personas living somewhere coherent, about 125 activities across 17 sports,
  multi-device outings, segments, routes, participations, comments,
  reactions, an API token and a webhook, all driven through the ordinary
  services and idempotent; the federation ring keeps the minimal dataset.

### Changed

- A participant of a published source reads the standard publication
  presentation instead of the metrics-only one.
- The REST `Workout` schema: `import_format` and `import` may be `null`, and
  `links.track` and `links.original` are absent on a credited workout.
- Instance metrics and the administration dashboard count recordings only,
  so a credited outing is counted once.
- Segment counters (`efforts_count`, `athletes_count`, the participant
  count) count recorded efforts only.

### Fixed

- Deleting a workout now refreshes the counters and personal-best flags of
  the segments it had efforts on; they kept counting the deleted efforts.
- Inviting an account again after a withdrawal answered 500.
- A deleted account showed its former name on the participants card and in
  follow, reaction and participation notices; it now reads as a deleted
  account.
- Deleting an account left its participations as a participant live.
- Long rides no longer fail their laps and places when a profile holds many
  climb candidates.
- Two matching jobs of one account finishing together no longer race on its
  records.
- Interval detection, resampling and course matching are linear on long
  tracks: a 92 km loop no longer needs 700 MB, a 9 000-point run no longer
  22 s.
- The progression and statistics charts work again for English accounts.

## [0.6.5] - 2026-10-13

### Added

- Every course is named after the place at its midpoint: one reverse lookup
  to the configured geocoding provider, made once after creation and paced
  with workout toponymy (`segments.place_name`, `place_status`). A recovery
  job retries recent failures, and existing courses are geocoded from the
  audited « Lieux des segments » action on `/admin/jobs` or
  `bin/rails segments:places`. The place never federates.

### Changed

- Segment leaderboards follow their reader: an athlete appears as soon as
  their workout is published with its route, to everyone who can see that
  workout, whatever the segment's own visibility (which now only decides who
  sees the course). A « Tout le monde / Mes abonnements » switch narrows a
  board to the accounts you follow, ranks read « among the athletes you can
  see », and your own line says who sees you or why nobody does. Names show
  to your followers and to the course creator; everyone else reads an alias.
- The publishing profile's « Classements de segments » setting is removed: a
  passage appears only when the publication shares its route, and each board
  can still be left from its page. Athletes who had turned the setting off
  appear again wherever their route is shared.
- The Segments index is a list instead of a grid of image cards: a table
  from `md` up and stacked rows on phones, with a course glyph, the name,
  the nearby place, sport, distance, D+, average grade, a mini elevation
  profile, the board's record (under the alias rules) and the viewer's own
  best time with their standing. Sport pills, sortable columns (record and
  best included, empty values last) and endless scroll follow the workout
  list. An all-sports course takes one row per sport it was run in, named
  « Segment (Sport) », each with that sport's record and best.
- Action buttons follow one placement everywhere — form footers, dialogs and
  inline card actions: from `md` up they sit on the left with the primary
  action left-most, and on phones on the right with the primary action
  right-most, under the thumb (`DESIGN.md` §10.3). The primary always comes
  first in the markup, so the two-step verification page now submits on
  Enter instead of cancelling.

### Fixed

- Downloads work in the iOS companion — the original file and the GPX of a
  publication, a received note or a received course — whose web view cannot
  save an attachment on its own: the links hand the URL to the app, which
  fetches the file and offers it through the system share sheet.

### Security

- The REST API's `Idempotency-Key` replay store keeps its response bodies
  encrypted at rest. A webhook signing secret could previously be kept in
  clear in a replayed response body; the rows kept so far are purged, and a
  retry whose first response is gone runs the request again.
- A token's REST API and `/mcp` requests count in one rate-limit bucket
  across every resource, as documented: Rails keyed the count by controller,
  so a token got the 300-requests and 60-mutations-per-minute limits once
  per resource.

## [0.6.4] - 2026-10-11

### Fixed

- The production image now contains `app/serializers` and `app/mcp`: the
  Dockerfile copies `app/` one directory at a time and listed neither, so
  the REST API's serialized endpoints and every `/mcp` request answered 500
  in production while development, which bind-mounts the tree, worked. A
  guard spec now fails when an `app/` directory is missing from either
  Dockerfile stage.

## [0.6.3] - 2026-10-11

### Added

- `[devdoc:mcp]` specifies a Model Context Protocol endpoint for AI
  assistants; `DESIGN.md` gains the §19.27 copy and the location badge.
- `POST /mcp` serves AI assistants statelessly behind the API token boundary
  (`read` scope) with three read-only tools: `list_workouts`,
  `get_workout_context` (metrics, data-quality findings, laps and detected
  sections, splits, best and segment efforts with the athlete's own history,
  records, equipment, the four weeks before) and `get_workout_series`
  (measurements over a distance or time range, never a coordinate).
- Each API token carries a location level for AI assistants, chosen once at
  creation — none (the default), tracks without the privacy zones, or
  complete tracks — capped instance-wide by `MCP_GEOMETRY_MAX` and mentioned
  in the creation mail. « API et webhooks » lists it and gives ready-to-paste
  configurations for Claude Code, opencode and `mcpServers` clients.
- `/metrics` exports `allure_mcp_requests_total{method,tool,outcome}`.

## [0.6.2] - 2026-10-11

### Added

- `[devdoc:api]` specifies the public REST API (`/api/rest/v1`, scoped API
  tokens), signed webhooks and the OpenAPI 3.1 document rendered by an
  embedded Scalar reference at `/developers/api`; `DESIGN.md` gains the
  glossary terms, the `/settings/api` and `/developers/api` anatomies and the
  §19.26 copy.
- API tokens: « Paramètres → API et webhooks » creates scoped tokens (shown
  once, up to a year, at most 20 usable), lists their last use and revokes
  them; creation and revocation are mailed. Not shown in the iOS app.
- The REST API's first, read-only operations: the account, the sport catalog,
  workouts (filtered and paginated), a workout's GeoJSON track and original
  file, equipment and publishing profiles, documented by an OpenAPI 3.1
  document every request spec is checked against.
- The REST API reads a workout's laps, splits over any distance, best efforts
  and segment efforts, and the account's records.
- The REST API edits workouts (title, description, notes, sport, commute,
  equipment) and deletes them as the website does, and imports files: an
  import answers at once and is followed until it finishes, can be cancelled,
  and is marked « API » on the import pages. A retried request with the same
  `Idempotency-Key` never imports twice.
- The REST API publishes workouts with the account's publishing profiles:
  a preview says what would be shared and returns the sentences to show,
  publishing needs an explicit acknowledgement, and a scheduled publication
  can be rescheduled, published now or cancelled; a live one can be deleted.
  The same rules as the website apply, privacy zones and safety delays
  included.
- The REST API reads what the account may read on the website: the feed
  (with the Public switch), a publication or a received note with its track,
  route image, comments and reaction counts, and the account's followers and
  followings. A field the author did not share is absent, and anything the
  website would not show the account answers 404.
- A workout's API representation names where it came from and, for a figure
  a data anomaly makes wrong, its plausible value.
- Webhooks: « Paramètres → API et webhooks » adds addresses Allure calls when
  a workout is imported, analysed, edited or deleted, and when a publication
  goes live, is withdrawn or fails to publish automatically. Each call is
  signed (Standard Webhooks), retried for about 21 hours, never carries a
  track or a file, and is listed with its outcome; a test can be sent and a
  call sent again. The same is available through the REST API.
- Webhooks also announce new personal records, segment efforts of recent
  workouts, comments, reactions, follow requests and acceptances,
  participations, and connected services that need attention — whatever the
  in-app notification settings. Allure notifies the account when it stops
  calling one of its webhooks.
- The administration's account page lists the account's API tokens and
  webhooks (prefixes and hosts only); the operator can revoke a token or
  disable a webhook, both recorded in the audit log. `/metrics` counts API
  tokens, API requests, webhook endpoints and deliveries.
- « API » in the footer opens the interactive reference (`/developers/api`),
  where a member can try each operation with their own token.
- The segment tab of a workout's analysis shows each effort against the
  personal best on that segment (« vs RP »): a slower effort its gap, the
  record its margin over the second best time. Owner-only, never published.

### Changed

- The Progression trend is drawn on a regular grid with straight segments,
  so it no longer overshoots or runs backwards beside a long gap; it is
  dotted under five outings and across a long gap.
- Place names are geocoded by the server — at import, after a re-analysis
  that moves the track or changes its elevation, and by a recovery sweep —
  instead of when the owner opens the workout. A sport change alone no
  longer re-geocodes. The operator can re-geocode outdated workouts from
  `/admin/jobs` or `bin/rails workouts:toponymy`.

### Fixed

- The time-zone menu submits the zone's IANA identifier, so saving a zone no
  longer fails, and the stored zone is preselected.
- A Garmin Connect link spec no longer fails once the date pinned in its fake
  token has passed.

## [0.6.1] - 2026-10-10

### Added

- Automatic publishing ([AUTO-PUBLISHING.md](docs/dev/AUTO-PUBLISHING.md)): a publishing profile can
  be marked automatic — off by default, one per audience, turned on only with
  an explicit acknowledgement, optionally excluding commutes. Each new import
  is then published through the ordinary publisher, with the profile's delay,
  once its elevation, segment matching, places and route image have settled.
  Activities older than 7 days, file batches over 5 entries and date-range
  retrievals are skipped; a wait that has not settled after 6 hours fails and
  tells the owner, who can also decline a waiting publication from the
  workout page. The profile form and list, the import surfaces, the import
  progress and two new notifications (`auto_published`,
  `auto_publication_failed`) explain the option.
- Garmin Connect, EXR and iGPSPORT show their own monochrome mark beside
  their name on the connection cards, the import tabs and the remote panel
  (`DESIGN.md` §6.4).
- Allure flags the readings that look wrong in an activity's original file
  ([WORKOUT.md](docs/dev/WORKOUT.md)): rejected and jumping GPS positions, speeds the sport
  cannot reach, shifted timestamps and interrupted recordings, missing,
  frozen or suddenly changing heart rate, elevation steps, and power or
  cadence spikes. Only what makes a figure wrong is put forward: a maximum
  speed, a distance or a maximum heart rate beyond the device's ordinary
  error shows its plausible value under the figure, taken from the device's
  own (Doppler) speed when the FIT file carries it, with a « Où ? » link to
  the stretch. Such a figure no longer holds a personal record, and a best
  effort the GPS lengthened is dropped. The rest waits in a « Qualité des
  données » analysis tab (`DESIGN.md` §15.5), with a switch to draw every
  finding on the map and the profile, each dash naming its finding through
  the page's shared tooltip; what a device does on most of its recordings is
  explained once instead of flagged. Nothing is corrected and nothing is
  published. `Allure::Gpx::Analyzer::VERSION` is 11; the audited
  `/admin/jobs` analysis backfill fills existing workouts.

### Changed

- The Progression chart of a segment, route or loop draws a robust trend
  (`Allure::Stats::RobustTrend`, [SEGMENTS.md](docs/dev/SEGMENTS.md)): a straight
  Theil–Sen line under eight outings, a robust LOWESS curve from eight, so a
  bad day no longer bends it and its ends are no longer flattened. It
  replaces the moving average over five outings.
- Each sport holding two efforts on a course gets its own Progression chart
  and data table, under its sport when there are several. The three best
  times keep their point and carry their trophy beside it on a short 45°
  leader instead of replacing it.

### Fixed

- Sign-in pages load in full in a browser, so password managers offer to
  fill them, including the operator's re-authentication reached from the
  account menu; the iOS companion keeps Turbo there.
- Notification avatars stay round beside long text, and a reaction or
  participation notice whose subject is gone names its still-existing
  account instead of calling it deleted.
- EXR workouts take the distance the ergometer recorded. EXR draws its Bled
  race course at twice the distance rowed, so a 500 m race showed 1 000 m and
  an impossible pace; every other world drifted by a few percent. The positions
  of a virtual platform's file are now fitted along the drawn course to the
  file's lap distance (`[devdoc:virtual-platforms]`), so distance, pace, splits, best
  efforts and the map agree with it. `Allure::Gpx::Analyzer::VERSION` is 10;
  the audited `/admin/jobs` analysis backfill reanalyzes existing workouts and
  re-renders the route image of those whose geometry moved. Existing
  publications keep their immutable snapshot.

## [0.6.0] - 2026-10-10

### Added

- Sessions expire (`[devdoc:auth]`): after 30 days without activity
  and at most 90 days after signing in, both configurable
  (`AUTH_SESSION_IDLE_DAYS`, `AUTH_SESSION_MAX_DAYS`). The session cookie is
  no longer permanent, the sessions table shows when each session signed in,
  and a daily job removes expired sessions.
- Closing a session or signing out everywhere asks for the password again
  when it was last proved more than 10 minutes ago (« Confirmez votre
  identité »).
- Two-step verification (`[devdoc:auth]`). After the password, an
  account confirms with an authenticator app, a passkey or security key, or
  a one-time recovery code; no session exists until it does. Every password
  account must set one up within 14 days (`AUTH_2FA_GRACE_DAYS`), reminded on
  every page; afterwards password sign-in leads only to the setup. The
  operator has no grace period, and the administration console asks for the
  second factor again every 15 minutes. The « Double authentification » card
  of the security settings manages the methods and the ten recovery codes,
  the code is typed in Tabler's six-slot input, which submits itself once
  complete,
  each change is confirmed by email, and the operator can reset an account's
  methods from the console or `bin/rails users:reset_second_factor`.
- Sign in with Google, Apple or an OpenID Connect provider (`[devdoc:auth]`
  slice 3), each enabled by the operator through its `AUTH_GOOGLE_*`,
  `AUTH_APPLE_*` or `AUTH_OIDC_*` settings. A first sign-in creates an account
  without a password after choosing a username (registration rules and
  invitations apply); an address already used by an account is refused rather
  than linked. The provider's own sign-in replaces two-step verification,
  except for the operator. The « Fournisseurs d'identité » card of the
  security settings links and unlinks providers, a password-less account can
  set a password (which starts the two-step grace period), and
  `bin/rails users:send_password_setup` emails a password-less account a
  password link. A Dex service (`oidc` Compose profile) provides a local
  OpenID Connect provider.
- The iOS companion signs in, creates an account, links a provider and
  confirms an identity through Google, Apple or OpenID Connect
  (`[devdoc:auth]`). The provider opens in the system sign-in sheet and
  hands the result back to the app through a single-use, one-minute link
  bound to a secret only the app holds. Google is offered in the app only
  where Sign in with Apple is too. Needs the companion's `auth-session`
  bridge; older versions show no provider button.
- Import from Garmin Connect (`[devdoc:remote-imports]`), off unless the
  operator sets `GARMIN_CONNECT_IMPORT_ENABLED`. Garmin has no public API:
  the integration is unofficial, and Garmin may change it or refuse a server
  address. From « Services connectés », an account links Garmin Connect with
  its e-mail and password (sent once, kept only while the link task runs; a
  verification code is asked for when Garmin wants one), retrieves a date
  range — also from the import page's Garmin Connect
  tab — and is then synchronised every hour. Each activity arrives as its
  original FIT file, private until published; activities without GPS are
  skipped and none is imported twice. Gear can be retrieved as equipment.
  Disconnecting offers to delete what was imported, checked by default. A
  notification asks to reconnect when Garmin refuses the session.
  `bin/rails garmin_connect:probe` checks the sign-in against a real account.
- Import from EXR, the virtual rowing game (`[devdoc:remote-imports]`),
  off unless the operator sets `EXR_IMPORT_ENABLED`. EXR has no public API:
  from « Services connectés », an account signs in to its EXR account once —
  the password is sent once and kept only while the link task runs, only the
  site's persistent sign-in cookie is — then retrieves a date range or lets
  the hourly sync bring each new
  session's original FIT file, recognised as virtual rowing in its world.
  Signing out of the EXR site may require reconnecting.
  `bin/rails exr:probe` checks the account site against a real account.
- Administration of connected services (`[devdoc:remote-imports]`): a
  « Connexions » tab under `/admin/imports` lists every account's connection
  with its state, last sync, session end and last error — never a
  credential or the external account — and the operator can revoke one
  (audited; the owner is notified and keeps the imported data). The batch
  list filters by source and shows the trigger, `/admin/system` shows the
  provider flags, and the dashboard counts active connections and those to
  reconnect. Prometheus gains `allure_import_connections`,
  `allure_import_connection_sync_age_seconds` and
  `allure_import_connection_errors`; `allure_import_batches` gains a `source`
  label.
- A Progression chart on a segment, route or loop once you hold two
  efforts on it: your own times over time, your three best drawn as their
  gold, silver and bronze trophies, and a grey trend averaging five outings.
  It shows only your efforts and never federates; the chronological table is
  its text equivalent.

### Changed

- The settings area is one Tabler settings card: the grouped section
  navigation beside the content, a horizontally scrolling tab bar on phones.
  `/settings` opens the Profil page, the former settings hub is gone, active
  sessions are paginated and sortable, publishing profiles list as a table,
  and text and password fields are full width again.
- The security settings are laid out in three groups: two-step verification
  first, the password and identity-provider cards side by side, then the
  sessions, full width, with separate device, sign-in and last-activity
  columns and « Fermer toutes les sessions » in the table's header. The table
  never scrolls sideways on a phone.

### Fixed

- A bulk sport change or deletion no longer stops after its first 25
  workouts: the job lost its concurrency key when it re-enqueued itself,
  marked the operation failed and left the rest of the selection queued.
- A session restricted to setting up two-step verification is closed as soon
  as its account gains a factor elsewhere, instead of staying stuck on the
  setup page.

### Security

- Authentication proofs stay out of the logs: authenticator, recovery and
  provider codes, passkey assertions, the iOS handoff's secret and token, and
  Sign in with Apple's user data are filtered. A recovery code entered before
  this release may have reached the log; regenerate any unused code.
- Unfinished authentication steps are cleared at every sign-in and every end
  of a session, so the next person in the same browser can no longer enrol
  the previous person's authenticator secret, see their recovery codes or
  finish their provider sign-up; cancelling these steps no longer happens
  through a prefetchable link.
- The identity provider's assurance claim is read from the verified ID token
  only, and the iOS sign-in handoff is bound to the page that started it and
  refuses a cross-site start, in addition to its PKCE secret.

## [0.5.2] - 2026-10-08

### Added

- A workout can be published to its followers and to the public at once: one
  live publication per audience ([PUBLISHING.md](docs/dev/PUBLISHING.md)). Each reader is served
  the narrowest version they may read, on the page, the track and chart, the
  feed and the profile. The « Publications » card lists one row per
  publication with its own actions, and « Ajouter une publication » adds a
  free audience. Each audience keeps its own comment thread, the owner picks
  one, and a reply joins its comment's. Each remote peer receives a single
  Note, the narrowest its followers may read, decided at delivery time.

### Changed

- The workout list is reorganised (`DESIGN.md` §13, §20.4): the header leads
  with the activity tile, titles the page « Mes activités » and carries the
  live result count (« 37 activités sur 178 » while filtered), while only the
  card/table switch stays at its top right. The sport pills keep their name
  and count at every width and scroll sideways on phones; period and sort
  share one toolbar row beside the filter toggle; and the rarely used filters
  — custom dates, publication, commute, place, search — live in an off-canvas
  drawer, a bottom sheet on phones, that never opens by itself and applies
  with its own button. Only the drawer's filters are chipped and badged; cards
  and phone rows carry icon-only badges and an unpublished workout none; the
  table view scrolls endlessly through both its desktop rows and its phone
  list, appended rows join the bulk selection, and long titles wrap or
  truncate inside their frame.
- The personal hub follows the workout list's language (`DESIGN.md` §8.4):
  the header leads with the avatar, the display name, the handle and the
  workout count, the toolbar reuses the sport pills beside the period switch
  — native selects on phones — recent segments render as a table or stacked
  rows, and the sport mix prints each legend share. Selecting a week of the
  intensity pulse or a day of the calendar opens a callout floating over the
  card, pointing at the selection, with its facts and a light link to its
  workouts; the reading line stays fixed on the peak, and a week or day
  holding a single activity opens that activity directly. Numbers follow the
  locale everywhere — server `format_decimal`, chart `formatNumber` — with
  the narrow no-break space as the French thousands delimiter
  (`DESIGN.md` §3.5).
- The phone bottom bar carries Personnes in place of Paramètres: the people
  directory joins the five main destinations and settings stays reachable
  from the account menu (`DESIGN.md` §7.3). The web bar and the iOS
  companion's native tabs share the same list.
- A card whose whole surface is a link now tints its frame on hover and
  keyboard focus — a primary border mix and Tabler's hover shadow over 150 ms
  — instead of underlining the title (`DESIGN.md` §10.1). Workout cards,
  segment cards and feed items share the rule.

### Fixed

- A workout whose profile was recorded without elevation no longer draws its
  selected metric as the muted secondary trend: alone on the plot it takes the
  primary colour and the normal stroke, and short holes in a sensor's series
  (up to 100 m or 2 % of the plotted span) are bridged for the drawing only —
  never across a recording segment — while the tooltip keeps the recorded
  values. The workout title's capitals now start level with the sport tile and
  the header actions.

## [0.5.1] - 2026-10-07

### Added

- The iOS companion appears in another app's share sheet (and AirDrop) for
  GPX, FIT, TCX, KML and KMZ files: it stages the file and opens the batch
  import form, whose file panel receives the bytes through the new
  `shared-files` bridge component and names what it received
  (`[devdoc:import-sources]`). The fallback sport, the notes and the
  submit stay Rails'; an app without the component keeps the plain upload
  field, and no server endpoint is added. `npm run test:shared-files` pins
  the transfer contract in CI.
- Second and third personal places: the owner's second and third best time
  over a standard distance and on their own segment efforts carry a silver or
  bronze trophy (« 2e meilleur temps », « 3e meilleur temps ») in the
  Analysis tabs, the course page's « Mes efforts » and the hub's personal
  column. They are derived on read (`BestEfforts::PersonalPlaces`,
  `Segments::PersonalPlaces`), owner-only, and never published.

### Changed

- Records and ranks follow one rule (`DESIGN.md` §10.4): the shape says who
  you measure against — the trophy is a personal place, the laurel before a
  numeral a leaderboard place — and gold, silver or bronze says the place.
  `MedalsHelper` is the single entry point and the styles share one tier
  family; the unused medal ink tokens are removed. The segment card's « Vous »
  line takes the laurel, a private course's « Mon record » the gold trophy,
  public profile cards show the published record badge, every rank numeral is
  spoken (« Rang 4 »), and the best-efforts tab (`ti-stopwatch`) and the
  records empty state no longer wear a place-coloured trophy. The hub's
  « Derniers records » adds the best-effort distances and hides the types a
  sport cannot express, like `/me/records`. Wording settles on « Record »
  (`/me/records` is « Records » in both locales) and the course tile on
  « Mon rang ».

- The workout page is reworked for the web, phones and the iOS companion
  (`DESIGN.md` §20.3). The map leads the page and becomes the sticky left rail
  from 992 px; the header keeps Publish and `⋯` beside the title, the sport and
  date under it, the places and an icon-only audience pill below. The summary
  folds its recorded extra metrics on phones and names the unrecorded ones
  once (« Non mesuré pour cette activité : … »); the description has its own
  card. The profile chart takes the card's width with floating y axes (top
  value only), whole-kilometre ticks, dashed gridlines, a thinner grey
  secondary line smoothed at the plotted scale, and range-selection zoom
  (press-and-drag on touch) with a « Vue d'ensemble » reset; its route steps
  are one sideways-scrolling line, and on phones « Voir les données » is read
  by assistive technology only. The analysis tabs scroll on one line, its
  tables follow the card's own width, and a highlighted row shades the chart
  in the same ink as the map. Comments come before the « Publications » card,
  which lists each publication with its own actions, withdraws them all from
  its header and states what a profile shares as two lists instead of
  projecting the workout; « Voir comme vos lecteurs » opens the reader's view
  (`?as=publication`). The original-data card and the danger zone are gone:
  the `⋯` menu downloads the file and deletes the workout. Participants are
  invited from their card header. Touch maps use two-finger gestures, the
  feedback button slides away while scrolling down, and segments use the
  `ti-route` icon everywhere.

### Removed

- The candidate publication preview card and its Turbo Frame;
  `GET /workouts/:id/publication_preview` answers JSON only.

### Fixed

- A segment's personal best was only recomputed for its creator, so another
  athlete matching a shared course never got their `RP`; every athlete on the
  segment is now recomputed in one statement.

## [0.5.0] - 2026-10-07

### Added

- Comments on published workouts, local to the instance for now
  ([COMMENTS.md](docs/dev/COMMENTS.md)): every signed-in reader the publication serves,
  owner included, writes plain-text comments (2 000 characters at most) and
  one level of replies in a full-width « Commentaires » card after « Partage »,
  re-rendered inside its Turbo Frame and working without JavaScript. The
  author deletes a comment, the owner removes anyone else's — the author still
  sees it marked « Retiré par le propriétaire » — and a withdrawn comment with
  replies stays as a stub. The owner closes and reopens a thread at any time,
  and the new publishing-profile setting « Commentaires » (on by default,
  absent on older profiles and therefore open) freezes a closed thread into
  the snapshot and announces it to other instances as a `comments: closed`
  Note tag, which receivers store and honour. The owner and the answered
  author get the new `comment` notification (switch at
  `/settings/notifications`), feed cards show the thread's count, a deleted
  account's comments leave their threads, and the composer carries the
  mandatory §19.21 sentence (`DESIGN.md` §10.20). The thread belongs to the
  workout, so republishing keeps it; comments never enter a publication
  snapshot. Federation of the comments themselves follows in later releases.
- Comments federate directly between Allure instances ([COMMENTS.md](docs/dev/COMMENTS.md)). A received note carries the comments card: a reader's comment is
  stored on their instance and sent to the publication's origin, addressed to
  the owner alone, with the mandatory sentence saying the origin keeps a
  copy. The origin hosts the thread: it accepts the comment through its
  publication policy and notifies its owner, or refuses it — closed thread,
  audience, withdrawn publication, full thread — with a `Reject` that the
  author's instance shows as « Refusé : les commentaires sont fermés » or
  « Refusé par le propriétaire »; an owner's later removal travels the same
  way. The owner's own comments and replies reach the instances that received
  the publication, after the publication itself and never to a follower who
  joined later, and stop when the comment or the publication goes; an
  author's deletion follows wherever the comment went and takes the words
  with it — the row keeps only its identity, the sent `Create` is redacted
  and leaves the author's outbox, as for a deleted account. A public local
  comment is served as an object at `/api/v1/comment/:id`, a followers or
  withdrawn one never. Blocks and remote account deletions take an author's
  comments out of every thread here. `dip fed_test` and
  `dip fed_restricted_test` prove the round trips.
- The origin of a public publication relays its comments to every instance
  that received it ([COMMENTS.md](docs/dev/COMMENTS.md)): a reader on another
  instance, or a member of the origin's, now sees the whole thread on a
  received note, not only the owner's words. Each relayed comment is checked
  against its author's own copy before it is stored, and leaves wherever it
  went when its author deletes it, the owner removes it, or its author is
  blocked or deletes their account — the relayed copy takes its words along.
  A followers-only thread is never relayed. A reply that arrives before the
  comment it answers waits on its thread and joins it when that comment
  lands. The composer on a received public note says the origin passes the
  comment on to the other instances that received the workout
  (`DESIGN.md` §19.21). `dip fed_test` proves the relay and its withdrawal.
- The iGPSPORT import source accepts every computer of the protocol family
  (`[devdoc:import-sources]`), not only the BSC500: the BSC100, BSC200,
  BSC300 and BSC500 lines with their S, T and Max variants, the iGS630 and
  iGS800, the BiNavi and the BiNavi Air. Chrome's chooser filters by those
  name prefixes and `models.js` matches the chosen name again, refusing
  anything else with a translated message. The BSC500 and the BSC100S are
  verified on hardware; the panel now names the connected model and marks any
  other one « non testé » with a sentence pointing at the connection log. The
  source tab reads « iGPSPORT » instead of « iGPSPORT (BSC) ». Only the
  initialization and activity UART channels are required (the BSC100S has
  four), and the handshake's fifth query, which Gadgetbridge never sends, may
  stay silent. Requests go out as acknowledged pieces of the model's write
  size — 244 bytes for the BSC500, 20 for the BSC100S's MTU 23 and every
  untested model — and the iOS companion sizes them from the connection's
  MTU, so no request is ever sent as a long write, which this firmware
  mishandles. `igpsport_link_test.js` drives the link over a scripted
  computer and replays the BSC100S frames captured by the iGadgetBridge lab.

### Changed

- The publishing-profile form stores an unchecked setting as an explicit
  `false` instead of a missing value; every existing setting reads both the
  same way.
- The federation ring empties `GEOCODING_BASE_URL` over the developer's
  `.env`, so its seeded rides never call a geocoding provider, and its
  revocation checks wait for the peer to process the unfollow instead of
  racing it.
- The personal hub's detail pages live under `/me`: `/me/stats` and
  `/me/records` replace `/stats` and `/records`, whose addresses answer
  permanent redirects keeping the query string and the format. The `/me`
  header no longer repeats the public-profile link, which the account menu
  carries as « Profil public », and the companion drops the header avatar its
  native bar already shows. Below `md` the sport filter becomes a native
  select beside the period one, listing every sport practiced at least once,
  each select keeping the other's parameter; the recent-workout tiles take one
  more gutter step, and workout-card badges may use two lines of the title row
  so the title keeps its width.
- The iOS companion keeps the page's own heading, pretitle and spacing, as on
  the web, now that its native bar names the current section; the document
  title, without the ` · Allure` suffix, stays the bar's fallback outside the
  five sections.

### Fixed

- A publication's delivery summary, its route-image release and the
  operator's delivery tally read the publication's own `Create` by its object,
  so no other activity riding on the publication can be taken for it.
- In the iOS companion, the last form footer, pagination row or card action no
  longer ends under the native tab bar: the page reserves the bottom safe area
  (`env(safe-area-inset-bottom)`) plus half a spacer once the web bottom bar is
  hidden; browsers and older companions keep the web bar's reservation.
- An iGPSPORT download is copied into a container sized from its declared
  length instead of rebuilding the buffer for every notification — quadratic
  at the BSC100S's 20 bytes per notification — and its progress bar updates at
  most once per percent.
- The iGPSPORT panel's activity summary, empty state and select-all toggle
  showed raw message keys; the panel now receives every one of its messages.

## [0.4.2] - 2026-10-05

### Added

- Route images exist in a light and a dark variant, produced together under one
  generation marker: the light one keeps the raster-then-tile-less fallback, the
  dark one uses the configured dark map style and falls back to the dark
  tile-less renderer only. The account picks what it sees at
  `/settings/appearance` (« Images des parcours »): **Selon le thème** (the
  default) follows the page theme — the server paints the matching variant on
  the first frame and the `route-image` controller swaps it live on
  `allure:theme-changed`, in the browser and in the companion — while
  **Toujours claires** and **Toujours sombres** force one variant. A themed URL
  falls back to the other variant when the requested one is missing,
  `Workouts::RouteImage::VERSION` and `Segments::RouteImage::VERSION` move to 7
  so the owned sweeps converge the library, and federation advertises the pair
  as two `Image` attachments — the light one first, the dark one marked
  `allure:theme: dark` — so a peer that predates the property keeps the light
  image; remote receipt, purge, retention and replacement cover both blobs
  (`DESIGN.md` §15.4, [WORKOUT.md](docs/dev/WORKOUT.md), [FEDERATION.md](docs/dev/FEDERATION.md)).
- The workout list's table view supports bulk updates from `lg` up
  (`[devdoc:bulk-actions]`): a selection column and a bulk bar with the live
  count, a « Sélectionner les N activités filtrées » scope and synchronous quick
  actions (commute, equipment). A sport change or a deletion is frozen into a
  `WorkoutBulkOperation` draft, reviewed with its exact counts, exclusions and
  §19 copy on its own page, then executed by `Workouts::BulkOperationJob` —
  batched, resumable, cancellable, one operation per account — with each
  activity reporting a translated outcome. Foreign or malformed identifiers are
  dropped without a hint, the 500-workout cap is enforced before any write, no
  bulk action touches an existing publication, and the whole affordance is
  never rendered in the iOS companion, which also runs on iPad
  (`DESIGN.md` §10.19, §20.4).
- The iGPSPORT BSC import source borrows the iOS companion's CoreBluetooth
  radio when the app advertises its `igpsport` bridge component: the same
  panel, selection, progress, FIT re-validation and batch-form handoff, with
  connect, list, chunked download and disconnect replies pinned by Node tests.
  A companion without the bridge reads an update request instead of the
  desktop-Chrome requirement, and no server endpoint is added
  (`[devdoc:import-sources]`).
- The iOS companion draws its chrome natively (`DESIGN.md` §7.7): a companion
  advertising `topbar` receives the web topbar hidden, with a payload for the
  navigation, the account menu under the account name, the notification state
  and the Import action, and replies with the chosen control, which the hidden
  bar clicks so links and the sign-out form keep their Turbo behaviour; `tabs`
  hides the phone bottom bar and hands the same five labelled destinations to a
  native tab bar, each keeping its own history and path; and the account toggle
  draws the page's avatar — generated art included — as a PNG through the canvas
  bridge. Older companions keep the web chrome.
- The iOS companion's own Appearance setting governs its pages:
  `allure_companion_theme`, a cookie read only for `hotwire_native_app?`
  requests, answers `current_theme` before the account theme, so every page is
  server-rendered in the chosen theme with no flash of the wrong one; browsers
  keep the account theme untouched, and the companion hides the account theme
  card, where the cookie would make the control lie.

### Changed

- The hub's charts select before opening (`DESIGN.md` §15.1): a tap, click or
  keyboard choice on the intensity pulse, the activity calendar or the sport mix
  selects the week, day or sport and shows its detail in a panel under the
  chart, whose button is the only way into the filtered list; a long press then
  slide scrubs the selection without scrolling, a swipe that moves first still
  scrolls, and the hit zone is the whole week column, rest weeks included.
  Touch screens get 44 px panel actions and paging buttons and a taller
  sport-switch hit area, and floating tooltips follow a hovering mouse only.
- In the iOS companion the duplicated web chrome is trimmed: the topbar drops
  the brand and the theme toggle, the footer is not rendered, the document
  title loses the ` · Allure` suffix, the page title stays for assistive
  technology only, a header left with no visible content collapses, and the
  account menu gains the `Serveur` / `Server` entry, which the app intercepts
  to open its server chooser (`DESIGN.md` §7.7).
- The iOS companion now lives in its own `allure-ios` repository; the Rails
  checkout keeps the bridge contracts, the locale keys and the release gate,
  and an iOS-only failure no longer blocks Rails verification or the production
  image build.

### Fixed

- The hub's dead `--tblr-*` colour variables are replaced by the real tokens,
  restoring the figure hairlines, the pulse separator and the delta colours,
  and the third figure no longer indents on phones (`DESIGN.md` §15.1).

### Security

- Federated authority handling folds the host to lower case: `Authority.domain`
  and the new `Authority.normalize_uri` keep inbound rate limits and actor
  blocks consistent across host case variants, `FederationActorBlock` storage
  and queries normalize, both withdrawal sweeps reach case variants, and a
  data migration canonicalizes the existing `remote_domain`, `source_domain`
  and actor-block rows.
- A received Note or course can no longer declare an attachment on another
  host: the RemoteNote and RemoteSegment parsers skip an attachment whose
  authority differs from the author's, and `RemoteMedia::Fetch` re-checks the
  stored descriptor against the owner's source domain before signing anything.
- The configured operator username is refused in the `:self_registration`
  context; console creation and operator-issued invitations are unaffected.
- Inbox admission persists a fetched remote actor only after the signature and
  key owner verify, and caps the actor-document fetch at 256 KB, so an
  unauthenticated POST naming a fresh actor URI no longer costs an unmetered
  fetch and a document-sized `actors` row.

## [0.4.1] - 2026-10-03

### Added

- The owner can create the reversed copy of their own segment or route from
  the page's `⋯` menu, with a label that names the type. The copy preserves
  the kind (a reversed route stays a route, private), keeps the link to the
  source activity, and is matched against the owner's own workouts in the
  reversed direction only ([SEGMENTS.md](docs/dev/SEGMENTS.md)).
- The `/@username` listing follows `Workouts::PublicationPolicy`: public
  publications serve every member, and followers-only publications serve the
  owner and accepted local followers while restricted federation is enabled.
  The tiles count the same visible set, each card carries its audience badge,
  unpublished and scheduled publications stay hidden, and a parity spec
  guards the scope against policy drift ([PUBLISHING.md](docs/dev/PUBLISHING.md), [FEDERATION.md](docs/dev/FEDERATION.md)).
- Every active week of the hub's intensity pulse is a link: clicking a capsule,
  or pressing Enter with the keyboard cursor on it, opens the workouts list
  filtered to that week (`/workouts?period=custom&from=…&to=…`), carrying the
  page-level sport filter exactly like a calendar day. A rest week draws no
  capsule and is not a link (`DESIGN.md` §15.1).

### Changed

- Browser surfaces are members-only ([ACCESS.md](docs/dev/ACCESS.md)): every readable
  page — feed, publications, courses, profiles, avatars, browser media — now
  requires a session, and a visitor is redirected to sign-in and returned to
  the requested page once authenticated. Public keeps its ActivityPub
  meaning: remote peers still fetch public objects and media without an Allure
  account, and the signed wire contract is unchanged.
  `Workouts::PublicationPrincipal` separates the anonymous browser from the
  signed-in browser, the unsigned protocol and verified actors, and both
  publication policies deny the anonymous browser on a public audience. The
  feed's visitor intro card is removed.
- The hub's intensity pulse is one weekly waveform over the whole history,
  scored by `Allure::Stats::Intensity` against the history's strongest week:
  the selected period keeps the primary ramp and the rest of the history takes
  a grey ramp, so switching windows never redraws the shape. Older windows
  load from `GET /me/pulse` as the scroller reaches the left edge, `‹`/`›`
  page by a window, *Aujourd'hui* returns to the present, and every fetched
  window is scored against the same whole-history basis. The peak is named by
  the reading line alone — no *Pic* mark on the chart — and a period spanning
  a single week prints its week and facts without the peak wording. The facts
  line names the sports from the second one on, and the keyboard cursor walks
  the loaded weeks, announcing each one (`DESIGN.md` §15.1).

### Removed

- The "Mes classements" directory (`/leaderboards`) is gone: a course's board
  and the *Mon classement* tile on its page are the standing, the hub's latest
  segments keep the ranks of recent efforts, and the old address answers 404
  (`DESIGN.md` §8.1, §20.7).

## [0.4.0] - 2026-10-02

### Added

- EXR's Long Beach world (EXR 1.56) joins the virtual venue catalogue, so
  sessions on the Alamitos Bay / Marine Stadium waterfront are named from
  their start point; `Workouts::ImportDetection::VERSION` is 2 and the rebuild
  sweep re-locates the venue of stored sessions (`[devdoc:virtual-platforms]`).
- Every segment, route and loop now carries a frozen bounded elevation profile
  (`segments.elevation_profile`, up to 240 points) written once at creation:
  the segment page renders it as the course chart on the right of the sticky
  map rail, served at the course's visibility through
  `GET /segments/:id/chart` with its distance table as the text equivalent. A
  course received from another instance, or one built without usable
  elevation, shows the unavailable state; `Segments::BackfillElevationProfilesJob`
  fills legacy rows (`bin/rails segments:elevation_profiles`, audited at
  `/admin/jobs`).
- A signed-in viewer can copy another account's shared course into their own
  private segments from the page's `⋯` menu, in the recorded direction or
  reversed. The reversed copy mirrors the geometry and stored elevation
  profile, swaps ascent and descent and recomputes its signature; the copy is
  matched against the copier's own workouts only, and a reversed one only
  matches recordings made the other way ([SEGMENTS.md](docs/dev/SEGMENTS.md)).

### Changed

- The personal hub's first row is one period card instead of four metric
  tiles (`DESIGN.md` §8.4, §10.2, §15.1). A figure strip prints the period's
  activities, distance (one decimal), elevation and human-scale time as bare
  figures with their previous-window deltas, and below it the **intensity
  pulse** replaces the four trend charts: one mirrored waveform where every
  day, month or year is a capsule whose height and tint carry its 0–100
  score — moving time, distance and ascent in equal parts, relative to the
  window's strongest bucket (`Allure::Stats::Intensity`) — and every rest
  bucket is a muted dot on the baseline. The peak carries a *Pic* mark and a
  reading line names it with its facts; the active-bucket count, a single
  explanatory ⓘ hint and the values-table disclosure complete the card.
  `format_distance` accepts a `precision:` keyword.
- Ranks and records no longer share one pictogram (`DESIGN.md` §10.4). A
  leaderboard place renders its numeral, and the top three lead with the
  laurel of their place (`ti-laurel-wreath-1/2/3`) in the medal's colour — the
  round medal disc is gone. A personal record is always the gold trophy, and a
  summary tile marks a top-three standing with the same laurel on the medal's
  disc tint. A segment effort's RP badge stays gold with its rank marker
  beside it, `/records` and the hub's latest-records card drop the per-row
  cup, and `ti-medal` / `ti-trophy` no longer decorate the best week, the
  longest streak, the "ranked" badge or the leaderboards empty state.
  `MedalsHelper` exposes `rank_medal(rank, participants:)`, `record_cup` and
  `record_badge`.
- The segment page is reorganised around the course. The owner's publication
  state is a header badge, and the §19.15 sentence, the stale hint, the
  blocking warnings, the publish/republish/withdraw actions, the source
  activity, the leaderboard participation toggle and deletion all live in the
  page `⋯` menu. The Classements container previews the top 10 per sport with
  a *Tout afficher* action and keeps the participation state below the board;
  *Mes efforts* gains the sport-preferred pace or speed; the details card
  becomes a summary-tile grid (Distance, D+, and for a signed-in viewer Mes
  efforts and Mon classement). A shared course's menu also offers the two
  copies above.
- The map and the elevation chart share one hover cursor: the same ball with a
  surface ring marks the hovered point on both, the profile adds a thin dotted
  vertical rule, and the ball appears whichever side the pointer is on. The
  map reveals the cursor from a generous band around the route and hides the
  pointer while it is inside that band (`DESIGN.md` §15.1).

### Fixed

- Loop detection no longer creates a second private loop segment when a similar
  circuit already exists for the account. `Segments::LoopReuse` elects the
  oldest similar segment — geometry compared as point sets by
  `Allure::Geometry::Hausdorff`, so a different start point or sport still
  matches — and the workout attaches its efforts to it; the sport widens to
  "all sports" when the recordings disagree. `Segments::BackfillLoopReuseJob`
  converges already-duplicated loops onto the oldest one, audited at
  `/admin/jobs` and available per account at `/settings/data`
  ([SEGMENTS.md](docs/dev/SEGMENTS.md), `[devdoc:derivations]`).

## [0.3.7] - 2026-10-01

### Added

- Every course — segment, route or loop — now carries an owner route image:
  the same dedicated `route_images` worker as workout images, with the
  course-level medium smoothing and the MapLibre → raster → tile-less fallback
  chain. It is derived from the course's own geometry and served at the course
  visibility through `GET /segments/:id/route_image`, never as a raw storage
  URL. `segments.route_image_version` records the renderer generation, and the
  audited rebuilds are exposed on `/admin/jobs` and `/settings/data`;
  publication images stay snapshot media.
- Découvrir opens the courses as a map alone — every course the viewer may
  read, their own private ones included — through `GET /segments/discover_map`
  (bbox, feature cap, viewport-scaled simplification). Facts only, formatted
  server-side: name, sport, distance, participant count and course link. It
  centres on the reader's position when the browser permission is already
  granted and falls back to the last activity's start point.

### Changed

- The Segments index drops its tabs: the kind is chosen in the hub's segmented
  control (Segments, Itinéraires, Boucles) and Découvrir opens the map. Every
  visible course of the chosen kind now renders under one card anatomy — the
  derived route image or its skeleton, a sport tile, the facts line and the
  board summary — the viewer's own badged `À moi` beside their visibility,
  another owner's carrying its creator, participant count and aliased podium,
  and a private course showing its owner's personal record instead of a board
  (`DESIGN.md` §20.6).
- The workout elevation chart anchors its markers on the drawn curve again:
  the numbered toponymy places sit on the profile, and the climb and descent
  summits and the stops become rose pills of the same size, also on the curve,
  with only a crowded pictogram alternating above or below it; the route
  timeline's step dots become the same circles as the places and carry their
  step icon (`DESIGN.md` §15.1). The owner elevation-source switch moves from
  its own « Altitudes » card into the header `⋯` menu as a single toggle, with
  its pending and failed states (`[devdoc:elevation]`).

## [0.3.6] - 2026-09-29

### Added

- Opt-in delayed publishing: a publishing profile may impose a safety delay
  (1 day / 3 days / 1 week / 2 weeks / 1 month), overridable per publish. With
  a delay the publish creates a `scheduled` publication — frozen snapshot and
  pre-rendered route image, invisible locally and with no outbox activity —
  that activates automatically with its Create intent when the delay ends; the
  owner publishes now, reschedules, or cancels (terminal, no Delete activity)
  from the scheduled card, an actorless notification announces the activation,
  republishing withdraws the old publication immediately, and deleting the
  workout cancels it in the same transaction. The administration console gains
  the scheduled filter, operator cancellation and audit
  ([DELAYED-PUBLISHING.md](docs/dev/DELAYED-PUBLISHING.md), `DESIGN.md` §19.19).
- Typed reactions on publications and received notes: one active reaction per
  account and target, with four types (beer, energy, coffee, the neutral
  like). Repeating a type withdraws it, another type replaces it; a reaction
  on a received note federates as a `Like`/`Undo` carrying the type in its
  private property, one on a local workout never leaves the instance, and the
  owner gets a notification with its `/settings/notifications` switch. The bar
  renders in feed cards, on workout and received-note pages and in remote
  profile lists, inside a Turbo Frame ([REACTIONS.md](docs/dev/REACTIONS.md), `DESIGN.md`
  §10.17).
- Shared activities, first lot: the owner invites an account they already
  follow in either direction; the invited account confirms or declines, and a
  live row is a `credit` (the owner's workout counts for the participant) or a
  `link` (the participant's own recording names the source). One live row per
  pair, either party withdraws, a refusal is terminal for that pair, and an
  invited participant reads a metrics-only presentation of an unpublished
  source while geometry stays governed by the owner's publication policy
  (`[devdoc:shared-activities]`, `DESIGN.md` §10.18).
- Virtual platforms are recognised by identity: `Allure::Virtual::Platforms`
  bundles each provider's FIT `file_id` fingerprint, creator aliases, fallback
  sport and rendered worlds. EXR is named from its fingerprint — the device
  was previously unnamed — its worlds (Boston, Bled, Henley, EXR World) become
  the workout's place through the venue catalog, and a virtual sport is never
  reverse-geocoded; the unambiguous FIT `fitness_equipment` indoor sub-sports
  now resolve to their virtual sports (`[devdoc:virtual-platforms]`).
- Derived data has one rebuild model (`[devdoc:derivations]`): the new owner
  page `/settings/data` and the administration console launch owner-scoped or
  instance-wide rebuilds — one file parse reconciles the import facts (device,
  re-detectable sport, virtual venue) and the analysis, route images are
  versioned and re-rendered only when a re-analysis actually changed the
  geometry, and places and terrain elevation keep their own sweeps. The
  workout menu offers a one-off route-image regeneration.

### Changed

- The workout list speaks the hub's language: one sharing-state badge per
  card, the owner's record badge, sortable table headers with `aria-sort`, the
  hub's calendar windows and an always-visible sport ranking, month sections
  on the date-sorted card view, and an endless scroll that drops the
  separator a fetched page repeats (`DESIGN.md` §12.2, §13.1–13.3).
- The personal hub adapts to phones: native selects for the period, calendar
  metric and sport mix, a recent-segments table that shows the effort's own
  sport and two ranks (personal attempts and leaderboard standing), and
  narrower gutters.
- The topbar import action becomes an icon-only tile on phones with its label
  back on desktop, and the phone action cluster, notification badge and brand
  alignment follow (`DESIGN.md` §7.3, §10.3).
- Every remaining native `title` (theme toggle, sport tiles, records, GAP
  line, password reveals, feedback button) uses the shared Bootstrap tooltip
  (`DESIGN.md` §10.3).

### Fixed

- Workout-list month separators render like the feed's day rules: inside the
  cards grid Tabler makes every column a flex container, which shrank the
  heading to its label and collapsed the rule lines.
- `vite-plugin-ruby` 5.2.4 restores Rails' dev-server detection, so
  development stops serving the stale `public/vite-dev` build.

### Security

- `vite_ruby` 3.11 and `rack-proxy` 2.0.1 resolve GHSA-42qh-8mx8-7wqm in the
  development Vite proxy.

## [0.3.4] - 2026-09-25

### Added

- In-app notifications for follow events: a topbar bell with an unread count,
  a dropdown card with the latest items, and a paginated `/notifications` page
  with *Toutes* / *Non lues* filters and mark-all-read. A follow request
  notifies the followed account; an accepted request notifies the requester.
  Opening a notification reads it and opens the account or the decisions hub,
  and each account controls the two kinds at `/settings/notifications`. An
  entry is withdrawn when its relationship ends — decision, unfollow, block,
  or a deleted remote account — and never carries coordinates, workout
  content, or remote HTML (`[devdoc:notifications]`, `DESIGN.md` §10.16).

### Changed

- The workout elevation chart keeps its plot width on phones: the vertical
  axis titles are gone (each series' name and unit live in the legend, with
  three y ticks on phones), the secondary metric line is display-smoothed at
  the map's medium window while the tooltip and data table keep the recorded
  values, and toponymy places and analysis pictograms move to a numbered
  marker band at the foot of the plot instead of sitting on the curve
  (`DESIGN.md` §15.1).

## [0.3.5] - 2026-09-27

### Added

- Profile avatars: `/settings/profile` takes a PNG, JPEG, or WebP upload,
  validated and center-cropped to 512×512 with its metadata stripped, stored
  as a normalized WebP and served only through the application avatar
  endpoint; the proxied cached Gravatar (when opted in) and generated art are
  the fallbacks. Generated avatars are deterministic pink geometric art with
  no initials, seeded per account at creation and backfilled for existing
  accounts, and rotatable in place while the generated art is visible
  (`DESIGN.md` §9.2/§9.4, `[devdoc:product-ui]`).

### Changed

- Segment leaderboards switched to opt-out participation: a segment takes its
  visibility (private / followers / public) at creation, every matched athlete
  is ranked as soon as their workout is published with a publishing profile
  whose `segment` setting is on (on by default), and a per-segment exclusion
  replaces the former opt-in. Eligibility is derived on read, so a publication,
  exclusion, visibility, or privacy-zone change needs no refresh; existing
  leaderboards are preserved by the snapshot alignment
  ([SEGMENTS.md](docs/dev/SEGMENTS.md), [PUBLISHING.md](docs/dev/PUBLISHING.md)).
- The feed uses one card for local publications and received notes: a
  mandatory author header, the route image or its pending/unavailable state,
  compact primary metric tiles with the record stamp, and a three-line
  description. The stream is sectioned by publication day in the viewer's
  zone, a fetched page no longer duplicates the leading separator, and
  anonymous visitors get an instance intro card on the first page
  (`DESIGN.md` §8.3).
- The topbar lost its right-aligned settings dropdown — Settings stays one
  click away in the account menu and the phone bottom bar — and the day/night
  toggle now sits between the notifications bell and the account menu
  (`DESIGN.md` §7.1/§8.1).
- `Allure::Gpx::Analyzer::VERSION` is 9; the audited `/admin/jobs` analysis
  backfill reanalyzes existing workouts and corrects all three figures.

### Fixed

- FIT session elevation totals are read at their profile numbers (22
  `total_ascent`, 23 `total_descent`); the parser used the lap numbers, so a
  device with a running-power channel had its session power maximum stored as
  ascent (an Amazfit Balance 2 showed 443 m for a 298 m run and 397 m for a
  25 m one). The session total of that family is trusted again; complete laps
  still win and the computed profile remains the fallback ([FIT.md](docs/dev/FIT.md), `[devdoc:elevation]`).
- Consecutive points sharing a timestamp — a GPX export rounds to the second —
  keep their path length in the workout distance instead of being dropped: a
  6.4 km run exported as GPX read 5.9 km while its own geometry measured
  6.4 km ([WORKOUT.md](docs/dev/WORKOUT.md)).
- Local actors render through their account's avatar chain: the People list
  and notifications now show the uploaded avatar, the cached Gravatar, or the
  account's persisted seed instead of generated art seeded by the actor URI.
- A bare remote handle (`@user@host`, `user@host`, or `acct:user@host`) now
  resolves through WebFinger as a follow or unfollow target instead of being
  treated as a literal actor URI.
- The anonymous profile page aggregates its public tiles in SQL instead of
  loading every visible publication's sanitized route and chart arrays into
  Ruby, so its cost no longer grows with the account's published history.
- An out-of-range `page` parameter is clamped before pagination, so a
  malformed public link answers an empty page instead of a server error.

### Security

- A signed federated `Delete` may tombstone an object only when the object URI
  shares the sender's authority, mirroring `Create`: another instance's object
  can no longer be permanently censored with an attacker-owned tombstone
  ([FEDERATION.md](docs/dev/FEDERATION.md)).
- The outbound SSRF guard validates the IPv4 embedded in NAT64
  (`64:ff9b::/96`, `64:ff9b:1::/48`) and 6to4 (`2002::/16`) addresses,
  closing a loopback, link-local, or private tunnel through a NAT64 or 6to4
  gateway.
- WebFinger accepts a `self` link only when the actor's authority matches the
  queried handle's domain, so a domain can no longer point a handle at another
  instance's actor and make that handle display or follow the victim
  ([FEDERATION.md](docs/dev/FEDERATION.md)).
- Password-reset requests answer in constant time: the lookup and delivery
  moved into an always-enqueued job, removing a timing side channel that
  enumerated accounts.

## [0.3.3] - 2026-09-25

### Added

- The exporter publishes `allure_best_efforts_rebuild_duration_seconds`, a
  histogram splitting every best-efforts rebuild into its pure `compute` phase
  and its transactional `persist` phase, labelled `context` (`import`,
  `reanalysis`, `backfill`). It measures how much derived-data work actually
  runs under the write locks (`[devdoc:metrics]`).
- Display smoothing for tracks: workout maps carry an on/off toggle in the map
  options icon — now a compact icon button aligned with the colour selector —
  that persists the account preference, and the intensity is chosen on
  `/settings/appearance` (*Léger* / *Moyen* / *Fort*, default off at medium).
  Course (segment) maps and publication images are always smoothed at the
  medium level. Smoothing preserves the point count, so payloads, snapshots,
  metrics, hover and the colour ramp are unchanged (`[devdoc:maps]`).
- Rowing and virtual rowing display their pace over 500 m (`2:00 /500m`) in
  every tile, card, analysis table, leaderboard, record, stat and chart axis,
  in either unit system, instead of speed. Their fourth summary tile is average
  power when the file recorded it, otherwise ascent, and both speed tiles are
  hidden. The catalog carries the nullable `sports.pace_basis_metres`
  ([WORKOUT.md](docs/dev/WORKOUT.md), `DESIGN.md` §20.3).
- Standard-distance best efforts now cover rowing and virtual rowing with the
  Concept2 set (500 m, 1 km, 2 km, 5 km, 6 km, 10 km, half marathon, marathon),
  and the running profile gains the marathon. `best_efforts:backfill SPORT=`
  rebuilds one sport when a profile gains a distance
  ([BEST-EFFORTS.md](docs/dev/BEST-EFFORTS.md)).

### Changed

- The workout summary card drops its brand top accent. Its primary metric tiles
  use the h2 value size and a smaller unit, and align their value on one
  baseline across the row while the label may wrap to a second line; a tile
  whose value holds a record carries Tabler's faded trophy card stamp instead
  of the small trophy badge (`DESIGN.md` §10.2/§10.4/§20.3).
- The workout detail header leads with the sport tile at the workout-card size
  and the title: another account's workout carries its author line under the
  title, the sport label, audience badge, device and date follow below at the
  left margin, and the owner-only place line closes the block (`DESIGN.md`
  §7.4/§20.3).
- Best-efforts computation runs before the import and reanalysis transactions;
  only the row replacement stays inside them, so the `users` row lock taken by
  every workout insert no longer covers the CPU scan over the track
  ([BEST-EFFORTS.md](docs/dev/BEST-EFFORTS.md)).
- The seven personal-record winner queries of `Records::RecomputeService` are
  index-backed on `(user_id, sport_id, <metric>)`, so a mass import no longer
  sorts the account's whole history once per imported workout.
- Direction of travel is drawn as open chevrons — a rounded surface stroke over
  a wider track-coloured halo, one every 240 screen pixels — on the live map and
  every route PNG, replacing the filled notch shape. Each chevron is placed on
  the straightest candidate of its slot, so it never sits on a corner
  (`DESIGN.md` §15.2/§15.4, `[devdoc:maps]`).

## [0.3.2] - 2026-09-25

### Added

- The workout list filters on a recorded place: a Tabler dropdown combobox
  over every place the owner's workouts recorded, suggested on focus and while
  typing by the owner-only `/workouts/place_suggestions` endpoint (10 names,
  frequency order, never cached), applied on selection or submit, and matched
  as a case-insensitive substring of any recorded place. The filter is a
  removable counted chip, round-trips through pagination and endless scroll,
  and degrades to a plain text field without JavaScript (`DESIGN.md` §13.3).
- Every workout carries owner-only geocoded places assembled from the
  toponymy already stored, with no additional Nominatim call: the departure,
  the ranked route markers and the arrival, deduplicated and capped at three
  entries in route order, shown on the workout header, the owner's cards and
  the owner table as a pin line. `workouts.places` is the denormalization the
  lists read, `workout_toponymies.places` keeps the list beside its inputs,
  and the same pass indexes every recorded marker as a `workout_place_names`
  row for the owner's filter and autocomplete. The audited `/admin/jobs`
  places backfill recomputes both purely and offline ([WORKOUT.md](docs/dev/WORKOUT.md)).
  Places never enter a publication snapshot or federation.
- The workout list's card view reproduces the `/me` recent-workout
  presentation and scrolls endlessly: fully clickable cards with the route
  image, smart relative dates and the compact metric line, the next page
  loaded by an intersection observer while active filters round-trip, and the
  Pagy nav kept as the `<noscript>` fallback. The table view keeps its
  pagination (`DESIGN.md` §10.14/§20.4).
- The workout list hides its filter frame by default: the page header carries
  the filter toggle — with the active-filter count — and the card/table switch
  instead of the import and new-workout actions (the topbar keeps the standing
  import entry), the panel opens below as a bare collapse, opens automatically
  with active filters, remembers a manually opened state for the session, uses
  compact controls (`form-*-sm`, `btn-sm`) with a 44px hit area on coarse
  pointers, and disables its date fields unless the custom period is selected.
  The debounced search keeps the caret in its field across the automatic
  reload (`DESIGN.md` §7.4/§10.6/§13.3/§20.4).

### Changed

- The virtual rowing sport is labelled « Rameur » in French.

### Fixed

- A FIT recording whose device reuses the same `message_index` for every lap of
  an interval session no longer fails the whole import on the per-workout
  uniqueness of `laps.number`: the index still numbers the lap when it is
  usable, and a colliding index falls back to the next free number
  ([FIT.md](docs/dev/FIT.md)).
- Two effort-matchings for the same workout no longer race the unique
  `(segment, workout, occurrence)` key: `Segments::MatchWorkoutJob` locks the
  workout row for its transaction, so a run enqueued by an elevation
  reanalysis or a segment backfill while the import's own run is still working
  waits and re-reads the committed efforts instead
  ([SEGMENTS.md](docs/dev/SEGMENTS.md)).

## [0.3.1] - 2026-09-23

### Added

- Direction of travel on every track: surface-filled chevrons outlined in the
  track colour, about every 100 screen pixels of each recording segment, on the
  live map, the candidate publication preview, and every route PNG — cards,
  feeds, publications, and received notes, including the raster and tile-less
  fallbacks. Direction comes from the geometry alone, so no track payload,
  snapshot, or federated representation changes (`DESIGN.md` §15.2/§15.4,
  `[devdoc:maps]`).

### Fixed

- Existing production databases now receive the reference catalogs on boot:
  the web container runs `db:seed` after migrating, so the 0.3.0 sport
  additions (road cycling, gravel, electric, virtual running, virtual rowing,
  pool swimming, snowboarding, ski touring) appear without a manual step.
- `/settings/sports` only offers plausible choices per generic sport: tennis
  and padel no longer appear for running, nor halfbike and inline skating for
  cycling. Each generic has a curated, alphabetical target list whose default
  selection is the generic sport itself ([WORKOUT.md](docs/dev/WORKOUT.md)).
- Every sport dropdown (workout form, batch import, segment form, list
  filters, leaderboards, `/settings/sports`) is sorted by the localized
  display name, accent- and case-insensitively, instead of catalog order.
- Real-world FIT and GPX files import as recorded: an isolated record whose
  clock glitched backwards is dropped instead of rejecting the activity,
  Garmin-style chained companion files are accepted up to 64, and the point
  cap rises to 250,000 so a long ultra imports whole ([FIT.md](docs/dev/FIT.md)).
- A FIT recording whose clock jumps backwards by more than an hour — a device
  clock correction — restarts from the corrected time and discards only the
  records from the earlier epoch, instead of failing the import.

## [0.3.0] - 2026-09-23

### Added

- A `commute` boolean on workouts, orthogonal to the sport and with no effect
  on the analysis, records, or thresholds. It has a checkbox in the workout
  form, a tri-state filter on `/workouts`, and a badge wherever the workout (or
  a publication that shares the flag) is presented. A FIT session whose
  sport/sub-sport pair is a commuting pair records `Track#commute_hint`, which
  the importer persists beside the detected sport; the owner's checkbox is ORed
  with the file's statement. A publishing profile's `commute` setting (off by
  default, like `device`) shares the flag in the sanitized representation and
  as a `commute` presence Note tag, parsed by remote Allure peers and rendered
  as a badge. [WORKOUT.md](docs/dev/WORKOUT.md) and [FEDERATION.md](docs/dev/FEDERATION.md) are the contracts.
- Eight sports: `cycling_road`, `cycling_gravel`, `cycling_electric`,
  `running_virtual`, `rowing_virtual`, `pool_swimming`, `snowboarding`, and
  `skiing_touring` (36 active sports). FIT/GPX/TCX detection now routes
  explicitly: road, gravel, e-bike, virtual, treadmill, pool-swimming,
  snowboard, and backcountry pairs resolve to their own sport instead of the
  nearest generic one.
- Per-account sport defaults at `/settings/sports`: when an import detects a
  generic sport (`cycling`, `running`, `walking`), the owner's preferred
  variant of the same icon family is used instead. The mapping applies to
  detection only — an explicit detection, the import fallback, and existing
  workouts are never changed ([WORKOUT.md](docs/dev/WORKOUT.md)).
- A per-sport icon set: every one of the 36 sports ships its own inline SVG
  partial (`app/views/sports/icons/`), plus six family fallbacks for a remote
  sport the local catalog does not know. The cycling variants stay
  distinguishable — bolt for electric, screen for virtual, terrain for gravel,
  knobby tires and a climbing tilt for mountain biking, pannier for trekking,
  speed lines for road — on the same bike base, and no sport is drawn from the
  icon font (`DESIGN.md` §6). The styleguide gains an icon proof sheet at every
  tile size.
- Shape-matched skeletons for asynchronous surfaces: the owner's workout card
  reserves its 16:9 top until the route image is attached, the candidate
  publication preview swaps in a skeleton with the same metric grid and map
  footprint, and the endless feed reveals item-shaped skeleton cards while the
  next page loads. Every decorative block is `aria-hidden` and a `role=status`
  sentence carries the wait.
- The owner's workout summary explains an elevation-less activity in one line
  (`Altitudes`), naming the cause and the single action that fixes it: the
  sport does not record elevation, the instance has no provider, the account
  has not opted in (linking to `/settings/elevation`), the enrichment is
  pending, failed or covered nothing (retrying the DEM request), or a cached
  terrain profile is ready but not applied yet. Non-owner pages and publication
  snapshots never render it.
- The `/me` hub trends follow the period's own grain: daily columns for the
  week and the rolling 30 days, a monthly area for the year, and a yearly area
  over the whole history for "Tout", whose total matches the printed tile.
  Every metric tile and the calendar card carry an ⓘ hint naming the metric,
  the plotted grain, the exact window and the delta's comparison basis, and
  year anchors now sit under the calendar grid.

### Changed

- `cycling_sport` became the generic `cycling` catch-all (label "Cycling"), and
  `cycling_transport` was deleted: the commute flag replaces it. The migration
  reassigns dependent rows, deletes the derived record rows, and normalises the
  retained publication, remote-note, and remote-segment representations that
  still named either slug. Snapshots stay immutable otherwise.
- `Allure::Gpx::Analyzer::VERSION` is 7: exact `<ele>0</ele>` placeholders are
  treated as missing on a partially recorded profile before any terrain
  override (a fully recorded segment keeps its zeros as sea level), so an
  elevation-less file reports no profile instead of a flat zero one. The
  analysis backfill re-reads existing workouts.
- Workout cards top-align the sport tile, title and audience badge, and the
  title's stretched link now covers the whole card: the route image and the
  pending skeleton are no longer dead zones (`DESIGN.md` §8.4).
- The styleguide sport wall shows the 36-sport catalog.

### Fixed

- Provider names that were silently misclassified now detect their own sport:
  `EBikeRide` → e-bike, `GravelRide` → gravel, `VirtualRide` → virtual cycling,
  treadmill runs → virtual running, generic FIT swimming → pool swimming, and
  backcountry ski → ski touring.
- The endless feed stopped after page 2: the infinite-scroll controller read
  the next-page URL from the sentinel, which never carries it, instead of the
  fetched wrapper, so the chain now follows to the end.
- A terrain-elevation request that can never succeed no longer leaves the
  workout pending forever: `Workouts::ApplyElevationSourceJob` clears the
  request when the profile is unusable and on terminal discard, keeping the
  failed and unavailable states retryable.

## [0.2.8] - 2026-09-21

### Added

- Terrain elevation for workouts without altitude (`[devdoc:elevation]`). When
  the instance configures an OpenTopoData-compatible `ELEVATION_BASE_URL` and
  the account opts in from `/settings/elevation`, an elevation-less workout is
  enriched after import from the configured dataset: coordinates are sampled
  every 50 m (at most 100 per request, tuned by `ELEVATION_SAMPLE_METRES`,
  `ELEVATION_REQUESTS_PER_SECOND`, and `ELEVATION_MAX_REQUESTS_PER_WORKOUT`),
  interpolated only inside contiguous valid runs, and analysed with a
  dedicated `dem` class (80 m smoothing, 8 m threshold) because a coarse DEM's
  short-wavelength error inflates ascent on long routes. The owner can also
  switch any workout between the device profile and the terrain profile; the
  cached `workout_elevations` row makes the switch instant, and existing
  publications never change. `/admin/jobs` gains the audited elevation
  backfill for existing elevation-less workouts. Federation representations
  are unchanged.
- Workout ascent and descent now prefer the device's own totals when the file
  carries them: the recorded laps when they cover at least 95 % of the
  activity, else the FIT session summary. The computed profile stays the
  fallback for GPX/TCX/KML and for files without totals.
  `Allure::Gpx::Analyzer::VERSION` is 6, so `Workouts::BackfillAnalysisJob`
  reanalyzes existing workouts; publications keep their immutable snapshot.
- The imported file's creator is shown as the recording device on the owner's
  workout header and original-data card. A publishing profile's `device` setting
  (off by default) shares it, bounded to 120 characters, in the sanitized
  representation and as a dedicated `device` Note tag; remote Allure peers parse
  it into the received note and render it on the note page.

### Fixed

- FIT files from devices that declare `position_lat`/`position_long` as uint32
  and write two's-complement negative semicircles now import correctly instead
  of turning western and southern coordinates into out-of-range points.
- Pagination links are built from the request path and encoded query string
  instead of `url_for`, which treated reserved keys such as `host`, `protocol`
  and `script_name` as URL-generation options. A crafted query string can no
  longer replace the host, inject attribute-breaking markup into the pager, or
  redirect the feed's infinite scroll.

## [0.2.7] - 2026-09-20

### Added

- A workout's sport can be changed from the edit form. Because the stored
  metrics depend on the sport's thresholds (`stopped_speed_threshold`,
  `records_elevation`, `grade_adjusted_pace?`), the change requires the original
  file and forces a re-analysis, then rebuilds best efforts and re-matches
  segments; the personal records of both the old and the new sport are
  recomputed, and existing publications keep their immutable snapshot.
- The analysis-version backfill has first-class launch surfaces: a
  `workouts:backfill_analysis` rake task and an audited « Recalculer les
  analyses » action in `/admin/jobs`, which shows how many workouts are on an
  older analysis version. Both enqueue the same self-rescheduling job
  ([WORKOUT.md](docs/dev/WORKOUT.md), `[devdoc:admin]`).
- The import page picks its panel from the `Allure::ImportSources` registry, so
  a source is a registry entry plus a partial (`[devdoc:import-sources]`). The
  first non-file source downloads recorded FIT activities straight from an
  iGPSPORT BSC bike computer over Web Bluetooth in desktop Chrome/Edge, then
  hands them to the existing batch form with its exact progress, duplicate
  skipping, and cancellation; no server credential or endpoint is added.

### Fixed

- Workers consume the internal `solid_queue_recurring` queue again, and the
  production worker consumes `federation` and `federation_media` instead of
  `default` alone. Command-style recurring tasks no longer pile up unconsumed,
  and the production federation inbox, delivery, and media jobs run. The
  recurring-tasks card now shows the queue the jobs actually land on instead of
  a misleading « default ». The backlog drains on deploy; to skip the burst,
  discard the orphaned cleanup jobs with `bin/rails runner
  'SolidQueue::Job.where(queue_name: "solid_queue_recurring").find_each(&:discard)'`
  and keep only the most recent pending `Federation::RecoveryJob` if the
  production federation backlog accumulated duplicates.

## [0.2.6] - 2026-09-20

### Changed

- The metrics engine is resilient to imprecise GPS ([WORKOUT.md](docs/dev/WORKOUT.md) and
  §8.9, analysis version 5). Implausible positions are removed before any
  metric: an iterative interior detour test for out-and-back spikes and a
  data-driven speed envelope that trims cold-fix and stale-fix artifacts at
  the track edges. The elevation profile is filtered once with a
  distance-window median and moving average, and ascent uses a threshold
  accumulator whose barometric/GPS threshold comes from the measured noise
  class, persisted on `workouts.elevation_filter`. The 3D vertical term, stored
  `ele`, and point speed (now a centred five-second window) read the same
  canonical profile; maximum speed uses a ten-second window. Consumers no
  longer smooth stored elevations a second time, and the matcher and lap
  rebuild versions bump so derived efforts and laps are recomputed. Run
  `Workouts::BackfillAnalysisJob.perform_later` after deploying.
- Publishing endpoint masks now control privacy-zone filtering
  ([FEDERATION.md](docs/dev/FEDERATION.md)): an unchecked `mask_start` or `mask_finish` exempts that
  endpoint from zone filtering — its points stay visible from the endpoint up
  to the route's first exit from every zone (start), or from its last entry
  to the end (finish) — while interior points stay filtered and a route that
  never leaves a zone keeps no exemption. Publication readiness warns when an
  unmasked endpoint will stay visible inside an active zone.

### Fixed

- Batch imports discover every source entry before importing: each archive's
  manifest is read first (ZIP central directory, no extraction), so the
  progress bar and waiting queue carry the true total from the first poll
  instead of reaching 100 % while files remained. The page now shows the
  waiting queue, the current file, status badges, and a completion notice
  with the activity list.
- Local followers accepted by the owner can now see the map and elevation
  chart of a followers-only publication: viewing it passed no browser
  principal, so the sanitized route and chart were hidden.

## [0.2.5] - 2026-09-19

### Added

- A Prometheus exporter at `/metrics` for Grafana (`[devdoc:metrics]`): bearer
  `METRICS_TOKEN` access (404 while unset), `yabeda-rails` request metrics,
  Solid Queue queue/process gauges, federation status counts, activity-based
  active and connected user metrics, storage and database sizes, and Ruby
  process basics. Database aggregates are cached for 15 seconds, and the
  exposition never carries domains, identifiers, coordinates, or payloads.
  The console and the exporter share the same vocabulary and definitions
  (`Users::Engagement`, `Metrics::Catalog`), enforced by a guard spec, and the
  administration dashboard's Accounts tile now shows connected and active
  accounts.

### Changed

- The `/me` personal hub is rebuilt around sport and period filters: a sport
  segmented control ranked by period activity (the active sport stays
  visible), the four calendar periods — this week, last 30 days, this year,
  all — with the previous window feeding the deltas. The metric tiles carry
  previous-window deltas and ApexCharts area trends; the calendar shows more
  weeks as the card widens without horizontal scrolling, defaults to
  duration, and gains rich per-sport tooltips and period paging; the sport
  mix is a primary-shade donut with its own metric selector and accessible
  table; new regularity (current week against the four-week average, streaks,
  active days, best week) and latest-segment cards replace the trend,
  sport-breakdown and equipment teasers; records link back to their workout.
  ApexCharts tooltips follow the theme, and every chart drops the library's
  default background.
- The twelve recent workouts are now fully clickable cards carrying a
  relative date ("Hier 09:30") and only the key metrics — distance, a
  human-scale duration, the sport-preferred average speed or pace, and
  elevation. The redundant footer button is gone, the grid fills at two,
  three or four columns, and "see all" keeps the active sport filter.
- Sport identity carries one brand-primary tint: every tile uses the same
  primary surface and glyph, never a per-sport hue, and on a workout card the
  printed sport name gives way to the tile's accessible name and tooltip.
- Avatar shapes now follow Tabler: a person's avatar — local or remote — is a
  circle, while non-person marks (sport tiles and the feature icon badges) use
  the rounded-square `avatar-square` shape. The sport tile is Tabler's avatar
  component, so its dimensions, corner radius, and glyph token come from
  Tabler.
- The development stack applies pending migrations when it boots: the `rails`
  service runs `db:prepare` before Puma, so `dip up` after pulling a migration
  no longer serves the pending-migration error page.

### Fixed

- The production web container applies pending migrations on boot. The
  generated entrypoint's argument check never matched Compose's
  `bin/rails server -b ...` command, so upgrades relied on the manual
  `db:prepare` step; the check now matches the command prefix and only the web
  container migrates.
- The route is drawn above every basemap geometry layer and below the label
  run on both the interactive map and the route PNGs. OpenFreeMap styles
  interleave symbols and geometry, so bridges hid the track on route images
  and, in dark mode, the whole road network hid it on the map.
- The spacing before the topbar actions (Import, account menu) is restored
  after the administration-console change in 0.2.4 removed it.

## [0.2.4] - 2026-09-18

### Fixed

- Publication route images and GPX for local viewers are now served through
  policy-authorized browser endpoints instead of the signature-only federation
  endpoints. A followers-only publication's media no longer 404s on your own
  feed card or workout snapshot, and public cards keep working anonymously.
  The signed wire endpoints are unchanged for remote peers.
- Workout imports tolerate a leading UTF-8 BOM or whitespace before the XML
  declaration in GPX, TCX, and KML sources. Real exporters emit that prologue
  and the strict pull reader used to reject the file as malformed; only the
  prologue is skipped, so genuinely malformed markup still fails.
- The parser detail of a malformed XML or FIT rejection is now logged with the
  source name, while the user-facing error stays localized and generic.

### Added

- The signed-in Publications feed always includes your own active
  publications, whatever their audience, independent of the Public switch.
  Each own item carries a `Vous`/`You` badge and its audience badge; the
  Public branch no longer duplicates them, and the anonymous surface stays
  public-only.
- The footer shows the running version, and after a release a what's-new
  dialog opens once per account with the curated notes from
  `config/release_notes.yml` (both locales). The footer version reopens it at
  any time; anonymous visitors see a plain version and a release without
  curated notes shows no dialog.
- The owner administration console lives at `/admin` behind the configured
  operator: an instance dashboard, a live background-jobs panel with retry,
  discard and pause controls, the expanded federation panel (moved from
  `/settings/federation`, which redirects), publication oversight with
  takedown, account suspension and reinstatement, single-use invitation
  management, import-failure inspection, system diagnostics, and an
  append-only audit log of every operator action.

## [0.2.3] - 2026-09-15

### Added

- The workout page's **Meilleurs efforts** tab now marks each distance that is
  the athlete's current record with a trophy, and removes it from the previous
  holder as soon as another workout beats it. Hovering, focusing, or pinning a
  row highlights its window on the elevation chart and the map; no persistent
  boundaries are drawn, since overlapping efforts would clutter the chart.
- The header record badge now covers every record the workout holds, not only
  best-effort distances: one combined trophy names the classic record types
  and the distances. The matching summary metric tiles carry the same trophy,
  and the biggest climb is marked when the workout holds `MC`. All of them are
  owner-only and disappear as soon as another workout takes the record.
- A new `records` publishing-profile setting (off by default) shares those
  markers: the immutable snapshot carries `record_types`/`record_distances`
  filtered by the sport's readable types and the enabled metrics, the public
  workout page shows the badge and tile trophies, and federated Notes deliver
  the markers as two dedicated tags parsed by remote Allure peers. The markers
  carry no numeric value and only refresh on republishing.

## [0.2.2] - 2026-09-14

### Added

- Standard-distance best efforts ([BEST-EFFORTS.md](docs/dev/BEST-EFFORTS.md)): the fastest elapsed
  time over 400 m to 30 km for running/trail and 5 miles to 80 km for the ride
  sports, computed inside a single recording segment with interpolated
  boundaries, shown on `/records` and on the workout page's Analysis card.
- A trophy badge on the workout page when it currently holds at least one
  best-effort record, and the `MC` biggest-climb record from the detected
  climbs. `/records` now also lists the per-distance effort records.
- `BestEfforts::BackfillJob` and `bin/rails best_efforts:backfill` rebuild the
  efforts for existing workouts from their stored track points; no re-analysis
  is needed.
- Grade adjusted pace ([WORKOUT.md](docs/dev/WORKOUT.md)): a flat-equivalent pace derived from
  the smoothed elevation profile with the Minetti 2002 climb polynomial and a
  descent cost curve. It renders on the workout summary and, as a
  quiet `GAP` line under the pace, in the owner-only Analysis tables (detected
  laps, efforts, intervals, splits) for every qualifying pace sport. The
  workout-level value is part of the published snapshot as a new metric key,
  accepted by remote Allure peers. Personal records, a chart series, and
  per-lap federation stay out of scope.

### Changed

- `Allure::Gpx::Analyzer::VERSION`, `Allure::Segments::Matcher::VERSION`, and
  `Laps::Rebuild::VERSION` move to 4, 3, and 3. Run
  `Workouts::BackfillAnalysisJob.perform_later` after deploying to reanalyze
  existing workouts; existing publications keep their immutable snapshot until
  republished.

## [0.2.1] - 2026-09-13

### Added

- Derived smart laps ([SMART-LAPS.md](docs/dev/SMART-LAPS.md)): rebuildable `detected_laps` rows
  projected from loop and route efforts, one pause lap per recording segment,
  elevation climbs and descents from a single shared profile, stops, and
  speed/power intervals, all named from the stored toponymy without new
  geocoding calls.
- One owner-only "Analysis" card merging segment efforts, every detected
  source, recorded laps, and splits: only non-empty tabs render, the card opens
  on the first with data, and the tables share one column vocabulary with the
  sport-preferred pace or speed, D+ and D−, and conditional HR, cadence, and
  power. Distance splits now report their own ascent and descent.
- An elevation chart that strictly follows the active tab: dashed boundaries
  for detected, recorded, and interval tabs, climb and descent pictograms on
  their own tabs, stop panels on the stops tab, and toponymy places always
  visible.
- A route-steps timeline listing the toponymy steps plus the active tab's
  discrete events (climbs, descents, stops, detected and recorded laps,
  segment efforts), scrolling horizontally on desktop and stacking on phones.
- Hover, focus, and pin synchronize a lap, stop, interval, effort, recorded
  lap, split, or route step with the chart band and the highlighted route
  slice; a hovered stop reveals its duration panel and enlarges its marker.

### Changed

- Climb detection is one shared profile with a forward extension to the true
  summit, and toponymy samples the same climbs it names; the legacy toponymy
  summit payload was removed and toponymy moves to algorithm version 7.
- The workout page merges laps, splits, and segment efforts into the Analysis
  card, so the sticky section nav carries five entries instead of six.

### Fixed

- Custom map markers keep MapLibre's absolute positioning instead of stacking
  in the document flow.
- Stop hover draws one enlarged icon and one duration panel, never a second
  glyph.
- Switching analysis tabs drops the highlight of a row the reader can no
  longer see.
- Signup emails are validated and the NIST single-factor password length is
  enforced; crafted sign-in and duplicate-email requests answer without 500s;
  IPv4-mapped addresses are normalized in the SSRF guard; inbox body reads are
  capped; blocks and tombstones are honored for cached remote avatars.

## [0.2.0] - 2026-09-12

### Added

- Shared segment courses: a segment's page, geometry, and map follow its
  `visibility` (private, followers only, public), while its leaderboard keeps
  following `leaderboard_audience`; sharing a course that crosses an active
  privacy zone requires a stored owner acknowledgment, and a corridor change
  asks for it again.
- Federated course distribution ([SEGMENTS-FEDERATION.md](docs/dev/SEGMENTS-FEDERATION.md) F0–F4): immutable
  `SegmentPublication` snapshots with explicit publish, republish, and withdraw
  controls; a course `Note` on the dedicated `/api/v1/segment/` path with a
  `sport_slug` tag and a required GPX attachment; received courses cached as
  `RemoteSegment` with per-account entitlements, media verification, and
  durable tombstones.
- Remote course pages at `/remote_segments/:id` with a map, media readiness
  states, and a copy-as-local action that creates a private owner-only segment
  the copier's own workouts are matched against; entitled courses also appear
  on remote profiles, and operator diagnostics count received courses and
  their media.
- `dip fed_test` and `dip fed_restricted_test` prove the course phases:
  delivery, duplicate idempotency, republish identity change, withdrawal with a
  surviving local copy, blocked-peer refusal, and followers-only authorization
  with signed object and media GETs and revocation purge.
- The shared leaderboard directory filters by active state, course kind, and
  sport.

### Changed

- A segment's visibility cannot become more restrictive than an active
  publication: the owner must withdraw or replace the publication first.
- The remote-media pipeline is shared between received publications and
  received courses through one attachment descriptor seam.
- Deleting a segment withdraws its active course publication first; account
  deletion withdraws course publications as well as workout publications.

### Fixed

- Unfollow, follow rejection, and blocking now withdraw remote course
  entitlements and purge followers-only course media, not only publications.
- A failed segment update (for example an unacknowledged privacy-zone corridor)
  rolls back completely instead of leaving deleted efforts or a cleared
  acknowledgment behind.

## [0.1.1] - 2026-09-12

### Added

- Instance presentation metadata (`INSTANCE_NAME`, `INSTANCE_DESCRIPTION`,
  `INSTANCE_HOST_NAME`, `INSTANCE_HOST_URL`): a "Hosted by" footer line,
  NodeInfo `metadata`, and the PWA description. Unset values stay hidden and an
  invalid host URL is ignored.
- All-sports segments: a segment with no sport is eligible for every sport,
  ranked separately per sport (`Segment (Sport)`), with one personal best per
  athlete and sport.

### Changed

- `/feed` merges the following stream and the instance feed behind a signed-in
  Public switch (URL parameter, default off, automatically on while the account
  follows nobody); `/following` redirects. The feed scrolls endlessly, with the
  real pagination kept as the no-JavaScript fallback, and pagination preserves
  the switch and every other filter.
- Local follows now require the target's approval like remote ones, decided
  from `/people`; a local decision changes state without federation traffic.
- The disabled followers profile names the operator gate instead of a future
  federation phase, and both the profile form and the publish selector explain
  the reserved followers audience.
- The course-only federated-segments contract is frozen in
  [SEGMENTS-FEDERATION.md](docs/dev/SEGMENTS-FEDERATION.md); implementation remains post-M5.

### Fixed

- The phone bottom bar no longer underlines or tints its links on hover or
  after a tap; keyboard focus keeps a visible ring.
- A freshly seeded test catalog no longer breaks the remote note view spec.

## [0.1.0] - 2026-09-11

### Added

- M5 Allure-to-Allure federation: exact-handle remote identity and follows with
  manual inbound approval, received public and followers-only publications with
  per-account entitlements, asynchronous remote media caching and GPX parsing,
  remote presentation with provenance, and the `/following` feed.
- The minimum federation safety gate: actor and domain blocks, inbound rate
  limits, per-authority delivery and fetch limits, remote-input caps, sanitized
  remote text, and the operator-only `/settings/federation` page with
  block/unblock, peer promotion, and media retry.
- Separately gated restricted federation behind `FEDERATION_RESTRICTED_ENABLED`:
  the built-in followers profile, promoted-peer delivery, signed object and
  media fetches, and revocation with purge on unfollow, rejection, block, or
  author deletion.
- The expanded two-node ring (`dip fed_test`), the restricted ring
  (`dip fed_restricted_test`), and the manual
  [FEDERATION.md](docs/dev/FEDERATION.md) Tier-3 checklist.

### Changed

- Remote content is proxied and cached: avatars, profiles, publications, and
  media always load from this instance, never from the origin.
- `FEDERATION_RESTRICTED_ENABLED` defaults to false everywhere, so followers
  publishing stays unavailable until an operator enables it and promotes the
  peer.

### Fixed

- Actor deletion now puts its explicit recipient audience on the wire, admission
  reads the `recipients` key, outbox actor currency is a creation-time
  invariant, and restricted delivery no longer requires promoted peers to have
  no shared inbox.

## [0.0.3] - 2026-09-11

### Added

- M4.5 publication hardening: preflight, central authorization, immutable
  publication ownership with retained local actors, atomic withdrawal and
  replacement, capability-gated delivery, recovery cleanup, and a live owner
  publication preview.
- Sanitized route images included in publications by default, with existing
  built-in profiles migrated to the new default.
- Author-attributed publications feed at `/feed`, two seeded development demo
  accounts with sample activities, a new Allure monogram with favicon and
  installable-identity assets, and a route-map colour-by selector that is flat
  by default and shades light to dark when a metric is chosen.

### Changed

- `/` dispatches by session: members land on the `/me` personal hub, visitors
  on the publications feed; Import is now a topbar-only action.
- Rebuilt sign-in, sign-up and password screens with a minimal auth shell,
  full-width password fields and a reveal toggle; the `/me` activity calendar
  is now a 53-week distance-ramped heatmap linking to each day's workouts.
- Sport identity uses larger neutral icon tiles with 29 globally distinct
  glyphs and no sport palette. The new brand primary `#c5426c` drives the UI,
  favicon, PWA chrome and route tracks, with a green start dot and a checkered
  finish flag.
- Tabler fluid horizontal layout, sticky workout map, cached avatars served
  through the application route, and landmark-aware route toponymy.

### Fixed

- Publication privacy, lifecycle and delivery gaps around followers-only
  handling, Create/Delete recipient resolution, and media retention.
- The feedback action retracts to a right-edge icon above the mobile bottom bar
  instead of covering it.

## [0.0.2] - 2026-09-08

### Added

- Adaptive owner route toponymy with dense track sampling, local settlement and
  route-detail lookups, climb and summit detection, loop-aware presentation, and
  responsive profile annotations synchronized with the route map.
- Keyboard-accessible segment creation with visible start/end point fields,
  responsive selection workspace cards, and preserved selections after validation
  errors.

### Changed

- Refined route endpoint and settlement selection according to route length,
  route passage, marker density, and exact chart endpoints.
- Production Compose now forwards the optional `GEOCODING_BASE_URL` setting to
  Rails and Solid Queue workers.

## [0.0.1] - 2026-09-07

### Added

- Owner-only route toponymy with privacy-conscious Nominatim enrichment,
  hierarchical place selection, elevation-profile annotations, and a responsive
  route timeline synchronized with the map.
