# Import sources contract

Workout imports come from pluggable sources: uploaded files, an archive, a
device, a remote provider or a manual entry. The import page carries one panel
per source, and the batch pipeline — discovery, exact progress, deduplication,
cancellation, toasts — stays the single import engine for every source.

## 1. Intent and non-goals

Adding a source is one registry entry and one panel, not a second pipeline.

Non-goals, deliberately:

- no dynamic third-party code loading: sources are built into the repository
  and reviewed like any other code;
- no server-side credentials in the file and device sources; the only non-file
  source there is client-side (browser or companion app) and stores nothing;
- no cloud provider for the device source; the remote sources are separate
  (`REMOTE-IMPORTS.md`);
- no route or GPX upload **to** a device: only import is in scope;
- no scheduled or automatic sync for the file and device sources: every such
  import is user-triggered. The remote sources lift this for themselves only.

## 2. Registry contract

`Allure::ImportSources` (`lib/allure/import_sources.rb`) is the single source of
truth:

- `Source = Data.define(:key, :kind, :icon)`;
- `kind ∈ :file | :device | :remote | :archive | :manual` (`KINDS`), where
  `:file` is an uploaded archive, `:device` is a browser-side download,
  `:remote` is a server-side provider, `:archive` is one uploaded export of
  another service read with its own metadata, and `:manual` is a workout typed
  in by hand ([MANUAL-ENTRY.md](MANUAL-ENTRY.md));
- `ALL` lists the registered sources; `for(key)` resolves a string or symbol;
- every source owns a translation at
  `workouts.batch_import.sources.<key>.label` and a panel partial at
  `app/views/workout_imports/sources/_<key>.html.erb`.

The import page (`/workout_imports/new`) iterates the registry: a pill tab list
when more than one source exists, one hidden panel per source, and the shared
options card below the panels — the fallback sport, the equipment, the commute
flag and the notes, which apply to every imported workout, and the title,
revealed only when exactly one file is selected and that file cannot hold
several entries (never a ZIP). The importer applies the title only when the
batch resolves to one entry, so a batch never titles every workout alike. The
file source keeps the form submit; a source that owns its own action (the device
source) hides the footer submit and submits the same form itself. The manual
source owns a form outside the upload form. The former single-file web form
(`/workouts/new`) redirects here; `POST /workouts` is gone. A `:manual` source
owns a form of its own, rendered after the upload form, which hides entirely
while it is selected; a refused manual form re-renders the page with that tab
selected (`data-import-source-initial-value`).

`spec/lib/allure/import_sources_spec.rb` guards unique keys, known kinds,
translated labels in both locales, and the existence of every panel partial.

## 3. File source

`file` is the existing pipeline: Active Storage attachments enumerated by
`Workouts::ArchiveReader`, imported by `Workouts::ImportBatchJob`. Its panel is
the multi-file field and keeps `accept` to the formats of
`Allure::ImportFormat`. A single selected file that cannot hold several entries
reveals the shared title field; the archive reader decides what a source yields
(a bare track file, a `.gz` and a `.kmz` are single-entry, a ZIP enumerates its
members).

### 3.1 Shared files from another app

On iOS, the companion (`../allure-ios`) appears in another app's share sheet and
in AirDrop for the track formats it accepts (GPX, FIT, TCX, KML and KMZ; the ZIP
and gzip archives stay web-only). The file is staged in the app, which opens
`/workout_imports/new`; when the batch form is reached, the app streams the
bytes into the existing input through the `shared-files` bridge component and a
`DataTransfer`, like the iGPSPORT handoff of §4.3. The shared options, the
fallback sport and the submit stay Rails'.

Bridge contract, every reply carrying a `status`:

| Request | Data | Replies |
|---|---|---|
| `connect` | — | `files` (`files: [{index, name, size, type}]`) or `empty` |
| `download` | `index` | `chunk` (`index`, `count`, base64 `data`, 128 KiB each), then `complete` or `failed` (`error`) |

Rails detects the registration in the user agent
(`hotwire_native_bridge?(:"shared-files")`) and adds the
`bridge--shared-files` controller to the file panel; without it the panel is the
plain upload field. The app keeps the shared files until the import page is
left, so a form re-render (a missing fallback sport, for example) still offers
them to the new request. No server endpoint is added: the batch form receives
the files.

### 3.2 Uploads: admission and retention

An upload is stored only while an import needs it. Every uploaded batch — the
file source, the Strava archive, the REST `POST /imports` — records its size in
`workout_import_batches.source_bytes`, and `Workouts::ImportAdmission` refuses it
before anything is attached when the account already has 3 file imports, or 1
Strava archive, queued or running, or when it would pass 6 GB uploaded in the
last 24 hours (counted from `source_bytes`, so purged uploads still count). The
web re-renders the panel with the reason; the API answers `429 import_limit`
with a `reason` (`too_many_active_imports`, `archive_in_progress`,
`upload_budget_exceeded`) and a `Retry-After`. Both web endpoints also carry a
per-account `rate_limit` of 20 per hour, a second guard only: the counted
admission is what bounds the disk.

Each imported workout keeps its own copy of its original, so a batch never reads
its upload again once it ends: `ImportBatchJob` and `StravaArchiveImportJob`
call `WorkoutImportBatch#release_sources!` on every terminal path (completed,
failed, cancelled). `Workouts::ImportSourceSweepJob` (daily, 04:45) purges
whatever a terminal batch still holds, and fails an uploaded batch untouched for
7 days, then purges it. `ImportBatchJob` runs one batch at a time per account
(`limits_concurrency`, group `WorkoutImportBatch`), like the archive job. Every
ZIP and KMZ is refused before rubyzip opens it when its central directory
declares more than 10 000 entries (`Allure::ZipDirectory`, which reads the count
from the end records alone; 100 000 for a Strava archive), since rubyzip builds
one object per declared entry before any later check runs.

Request bodies are bounded in three layers. The reverse proxy (documented in
`docs/site/install/reverse-proxy.md`) allows 2112 MiB on the three upload paths
— `POST /workout_imports`, `/workout_imports/strava_archive`,
`/api/rest/v1/imports` — and 32 MiB elsewhere; it is the only layer that refuses
before the body reaches the container. Puma's `http_content_length_limit`
refuses anything over the largest endpoint limit
(`Allure::RequestBodyLimit.max_bytes`, a guard spec keeps the two equal) before
buffering, declared or chunked. `Allure::RequestBodyLimit` (`lib/middleware/`,
first before every middleware that reads a body) then answers `413` before Rails
parses a body over its endpoint's limit: the archive plus 64 MiB on the archive
and API paths, 500 MiB plus 64 MiB on the file batch, 32 MiB anywhere else. In
the browser, the `upload-size` controller refuses the visible panel's files over
their limit before uploading, with the server's own `source_too_large` message.
A batch row, a few hundred bytes of history, is never deleted by the member; a
per-account storage quota over originals, uploads and photos is a later
contract.

## 4. Strava archive source

`strava_archive` (kind `:archive`) imports the ZIP Strava sends an athlete who
requests their data, applying `activities.csv` — name, type, description,
private note, commute flag, gear — to each original file, and creating the gear
the account lacks. Its panel owns its fields and its submit (`POST
/workout_imports/strava_archive`), so the shared options card and the footer
submit hide while it is selected, as for a remote source. It is always enabled
and needs no credential. `[devdoc:strava-archive]` is the contract.

## 5. iGPSPORT device source

`igpsport_device` downloads recorded FIT activities directly from an iGPSPORT
bike computer over Web Bluetooth. There is no cloud account, no server
credential, and no new server endpoint: the browser downloads the files,
validates them, and hands them to the same batch form.

The source covers every computer known to speak the protobuf-over-UART protocol.
Names are matched in full, as Gadgetbridge's coordinators do:

| Model | Advertised name | Evidence | Status |
|---|---|---|---|
| BSC500 | `BSC500` | hardware | verified |
| BSC100S | `BSC100S` | hardware | verified |
| BSC200, BSC200S, BSC300 | `BSC200`, `BSC200S`, `BSC300` | Gadgetbridge | untested |
| iGS630, iGS630S, iGS800 | `iGS630`, `iGS630S`, `iGS800` | Gadgetbridge | untested |
| BiNavi | `BiNavi` | Gadgetbridge | untested |
| BiNavi Air | `BiNavi Air`, possibly prefixed with `iGPSPORT` (Gadgetbridge's case-insensitive pattern) | Gadgetbridge | untested |
| BSC100, BSC100Max, BSC300T | variants of the names above | none | untested |

`app/frontend/lib/igpsport/models.js` is the browser's single list. Chrome's
chooser filters by name prefix only (`BSC100`, `BSC200`, `BSC300`, `BSC500`,
`iGS630`, `iGS800`, `BiNavi`, `iGPSPORT`), so the chosen name is matched again
and a device outside the family — an iGPSPORT light picked through the
`iGPSPORT` prefix, say — is refused with a translated message. Older iGS
computers (iGS620, iGS320…) are excluded: nothing shows they speak this
protocol. The panel names the connected model and marks an untested one with a
« non testé » badge and a sentence pointing at the connection log. The companion
keeps the same rules in Swift, pinned by the same name vectors.

The protocol notes and model names are informed by Gadgetbridge, the
open-source Android companion, credited in `NOTICE`.

### 5.1 Browser requirements

Web Bluetooth requires a secure context and desktop Chrome or Edge, and the
browser must support acknowledged GATT writes (`writeValueWithResponse`). The
panel shows the requirements instead of the controls when `navigator.bluetooth`
is missing or `window.isSecureContext` is false, unless the iOS companion lends
its radio (§5.4); a companion without that bridge is asked to update instead.
Docker containers and the Playwright browser cannot reach Bluetooth hardware;
device verification is a manual, host-browser step on `https://` or `localhost`.

### 5.2 Protocol modules

`app/frontend/lib/igpsport/` ports the verified wire behavior of the
iGadgetBridge lab (`references` are local and untracked; `docs/PROTOCOL.md`
there is the behavioral reference):

| Module | Responsibility |
|---|---|
| `constants.js` | NUS channel UUIDs and which are required, packet types, modes, service and command ids, timeouts, size caps |
| `models.js` | the chooser's name prefixes, the family's names, the verified models and their write sizes |
| `bytes.js` | hex/byte helpers |
| `framing.js` | CRC8-Maxim, `craftData`, `parseHeader` |
| `protobuf.js` | varint codec, activity payloads and decoders, init requests |
| `fit.js` | FIT CRC16/CRC32, `validateFit`, UTC activity filename |
| `link.js` | `Bsc500Link` (every model, despite the historical name): connect, five-step initialization handshake, activity listing, download stream |

Frozen protocol rules:

- every NUS channel the device exposes is subscribed before any request;
  channels 1 (initialization) and 3 (activities) are required, the others are
  optional — the BSC100S has no fifth instance;
- the five-step initialization handshake runs, in order, after GATT connect and
  before file operations; the first four steps are Gadgetbridge's own sequence
  and must answer, while the fifth (`DEV_VER_INFO / GET`), which Gadgetbridge
  never sends and whose reply the import ignores, may stay silent;
- a request is written as acknowledged pieces no larger than the link's write
  size, never as a long write, which this firmware family mishandles (one model
  acknowledged a long write it stored corrupted). Web Bluetooth exposes no MTU,
  so the browser uses the verified size — 244 bytes for the BSC500 (MTU 247), 20
  for the BSC100S (MTU 23) — and 20 bytes, valid at any MTU, for every untested
  model; the companion uses the connection's MTU − 3;
- activity listing calls `LIST_NUM_GET`, then `LIST_GET` with explicit inclusive
  page bounds, drops zero placeholders, and deduplicates timestamps;
- activity pages and downloads run on channel 3 as file-operation requests; a
  stray `FILE_SEND` result after a reply is logged and ignored;
- a download is one `FILE_GET` request; the device streams
  `[20B header][4B metadata size BE][file_download][FIT bytes]`, possibly in
  20-byte notifications whose first holds the header alone. The link copies the
  stream into a container sized from the declared file size (at most 64 MiB)
  instead of rebuilding a buffer per notification, reports progress at most once
  per percent, and applies a 20-second idle timeout;
- every downloaded file is validated (declared size, `.FIT` signature, header
  and file CRCs, and the device CRC32 when the metadata carries one — the
  BSC100S sends none) before it is handed to the import.

The modules are loaded with a dynamic `import()` so the protocol never enters
the main bundle.

### 5.3 Panel flow

1. connect (Chrome device chooser) → initialization → model (with the
   « non testé » badge and its sentence for an untested one), serial and
   battery; a refused name or a failed handshake releases the computer and keeps
   the failure in the status line;
2. "Lire les activités" lists recorded activities newest first with local dates
   and sizes;
3. selection with a select-all/clear-all toggle;
4. "Importer la sélection" downloads each selected activity with progress,
   validates it, builds a `File`, and assigns the files to the batch form's file
   input through a `DataTransfer` before submitting the form;
5. the existing batch page shows progress, deduplicates by digest, and marks an
   already-imported activity as a duplicate.

The controller releases the BLE connection on Turbo `disconnect` and guards
against unexpected disconnections, which reset the panel to its initial state.

### 5.4 iOS companion transport

WebKit has no Web Bluetooth, so the Hotwire Native companion (`../allure-ios`)
registers an `igpsport` bridge component and lends the phone's CoreBluetooth to
the same panel. Rails detects the registration in the user agent
(`hotwire_native_bridge?(:igpsport)`), adds the `bridge--igpsport` controller to
the panel element and sets the `igpsport-device` controller's `native` value;
the controller then instantiates `NativeLink`
(`app/frontend/lib/igpsport/native_link.js`) instead of `Bsc500Link`. Both expose
the same `connect`/`initialize`/`listActivities`/`downloadActivity`/`disconnect`
surface, so the panel, the selection, the progress, the FIT re-validation and the
form handoff of §5.3 are unchanged. No server endpoint is added: the batch form
still receives the files.

Bridge contract, every reply carrying a `status`:

| Request | Data | Replies |
|---|---|---|
| `connect` | — | `log` (`message`, `kind`) at any time; then `connected` (`name`, `serial`, `battery`), `cancelled` or `failed` (`error`); later `disconnected` when the computer drops the link |
| `disconnect` | — | none: the panel resets itself at once, as it does when the GATT server confirms a browser disconnection |
| `list` | — | `listed` (`activities: [{timestamp, fileSize}]`) or `failed` |
| `download` | `timestamp`, `fileSize` | `progress` (`received`, `expected`, at most once per percent), `chunk` (`index`, `count`, base64 `data`, 128 KiB each), then `complete` (`fileSize`, `fileId`, `fileName`, `fileCrc32`) or `failed` |

The app owns the device chooser (a native sheet listing the nearby computers
whose names belong to the family of §5), the Bluetooth permission and its
localized radio errors; every protocol rule of §5.2 is ported to Swift with the
same golden vectors and the app validates each file before handing it over. The
companion sizes its write pieces from
`maximumWriteValueLength(for: .withoutResponse)` — the connection's MTU − 3 —
because the `.withResponse` value is the 512-byte attribute limit, which
CoreBluetooth reaches through a long write. Rails resolves the `connected`
reply's `name` with the same list to show the model and its status; a name the
app accepted but the browser list does not know is shown as untested. The
companion releases the radio when the panel asks, when the page leaves the
screen, and when the computer disconnects.

## 6. Remote sources

A `:remote` source keeps the same panel contract but adds a server-side
provider: an encrypted `ImportConnection` per user and provider, an operator
enable flag, `list`/`fetch` operations, and the same batch discovery and
processing phases. `REMOTE-IMPORTS.md` is that design: the `garmin_connect`,
`exr`, `withings` and `zwift` sources, the `ImportSources.enabled` filter driven
by the operator flags, the `Workouts::RemoteImportBatchJob` that reuses the
batch pipeline with entries discovered by a provider listing, the original-FIT
rule for Garmin, the `/connections` area and the hourly sync. Nothing in the
file and device sources presumes it; the registry gains `remote?` and `enabled`
there.

## 7. Manual source

`manual` (`MANUAL`, kind `:manual`, icon `pencil`) is always enabled. It reads no
file and stores nothing in the batch pipeline: its panel posts to
`POST /workouts/manual` and creates one `origin: "manual"` workout through
`Workouts::ManualEntry`. [MANUAL-ENTRY.md](MANUAL-ENTRY.md) is its contract.

## 8. Verification

- `spec/frontend/igpsport_protocol_test.js` (`npm run test:igpsport`, also run
  by `.github/workflows/ci.yml`) pins CRC8 vectors, protobuf payload bytes,
  page-bound validation, activity-list decoding with the zero placeholder,
  metadata decoding, FIT validation, and the UTC filename against the reference
  implementation's golden vectors. `igpsport_native_link_test.js`, in the same
  script, pins the §5.4 reply contract: status routing, chunk reassembly in index
  order, progress, the single disconnection callback, and the model resolved from
  the app's name.
- `igpsport_link_test.js`, in the same script, drives `Bsc500Link` over a
  scripted Web Bluetooth computer: the accepted and refused name vectors (shared
  with the companion), the chooser filters, the required channels, 20-byte pieces
  on the BSC100S against one write per request on the BSC500, the silent
  `DEV_VER_INFO` tolerated while a silent required step still fails, and the
  BSC100S frames captured by the iGadgetBridge lab — a reply split from its
  header, the stray result, and a download whose first notification is the
  header alone, without a device CRC32 and with throttled progress.
- Request specs assert the picker, both panels, the JSON message value, and the
  companion variants (bridge registered, older app asked to update). A
  `shared-files` variant asserts the file panel's bridge and its absence for an
  app that does not register it. `spec/frontend/shared_files_test.js`
  (`npm run test:shared-files`, also run by `.github/workflows/ci.yml`) pins the
  transfer contract: the empty manifest, per-file chunk reassembly in index
  order, and a failed reply.
- The registry spec guards the plugin contract.
- Real radios have no automated coverage: the BSC500 and the BSC100S are
  verified manually on the host browser, and on an iPhone for the companion. The
  companion's own suite covers the Swift port of §5.2 with the same vectors and
  the link state machine over a scripted radio. The other models are untested
  until someone connects one; the badge and the connection log carry those
  reports.
