# Bulk actions contract

Bulk selection and bulk updates on the owner's workout list. The feature is a
desktop browser workflow: the selection UI renders only in the table view of
`/workouts` from `lg` up and is never rendered in the iOS companion. Every
operation reuses the shipped single-workout service; no publication, snapshot,
or federation rule is reimplemented here.

| Operation | Kind | Service reused |
|---|---|---|
| Trajet on/off | quick, synchronous | plain column update |
| Equipment add/remove | quick, synchronous | join rows + `Equipments::Totals.refresh` |
| Sport change | reviewable, background | `Workouts::SportChange` |
| Deletion | reviewable, background | `Workouts::WorkoutDeletion` |

## 1. Decisions

- Selection lives only in the table view (`DESIGN.md` §12.2, §20.4). The card
  view and its endless scroll are unchanged.
- The bulk bar and the selection column render only from `lg` (≥992 px) and are
  absent from the companion's HTML (`hotwire_native_app?`). Authorization never
  depends on width or user agent: every endpoint resolves through
  `current_user.workouts`.
- Selection never survives navigation as hidden state. A request carries either
  explicit workout short ids or `scope=filter` plus the allowlisted filter
  parameters, which the server replays through `Workouts::ListQuery` — the same
  class the list itself uses.
- Quick actions run synchronously in the request. Reviewable operations go
  through `WorkoutBulkOperation` / `WorkoutBulkOperationItem` and
  `Workouts::BulkOperationJob`.
- Caps: 500 workouts per operation. The cap is enforced before any write; a
  larger selection is refused with a translated message and nothing is changed.
- Foreign or malformed identifiers are dropped silently: a bulk endpoint never
  reveals whether another account's workout exists.
- The review page is the confirmation. Bulk deletion does not use the shared
  confirmation modal (`DESIGN.md` §10.10): the page states the exact counts,
  the exclusions and the mandatory §19 copy, and the review is frozen server
  side.

## 2. Selection

`Workouts::BulkSelection` resolves the request into an ordered list of the
owner's workout ids:

- `scope=filter`: `Workouts::ListQuery` replays sport, period, publication,
  commute, place, free-text, sort and direction parameters. The result is the
  whole filtered set, never only the rendered page. Order is the list's current
  sort.
- otherwise `workout_ids[]`: ShortUUID codes decoded with `Allure::ShortId`,
  looked up through `current_user.workouts`, and returned in submitted order.
  Invalid codes and foreign ids disappear without a hint.

The index view renders the allowlisted filter parameters as hidden fields of
the bulk form, so the filter scope is replayable; the server still treats every
value as untrusted input.

## 3. Quick actions

`Workouts::BulkQuickAction` applies one action to the resolved ids inside the
request:

| Action value | Effect |
|---|---|
| `commute_on` | sets `commute` for workouts where it is not already set |
| `commute_off` | clears `commute` where set |
| `equipment_add:<id>` | inserts missing join rows; only the owner's active equipment is eligible |
| `equipment_remove:<id>` | deletes the join rows that exist |

The action counts only actual changes, and the flash message reports that
count. Equipment totals are refreshed once per equipment, after the join rows
are written — never per workout.

## 4. Reviewable operations

A reviewable operation starts as a `draft`:

1. `POST /workouts/bulk/review` resolves the selection (cap included) and
   creates the operation plus one item per workout, in selection order. A new
   draft cancels the account's previous drafts.
2. `GET /workouts/bulk/:id` renders the review while the operation is a draft:
   the exact count, the date range, the sport breakdown, the publication
   counts, the exclusions it already knows (workouts without an original file
   for a sport change), and the operation form.
3. `PATCH /workouts/bulk/:id` confirms: parameters are validated (the sport
   must exist and be selected), the operation becomes `queued`, and the job is
   enqueued. Enqueue failure returns to the draft and says so.
4. `GET /workouts/bulk/:id` renders progress once it is not a draft;
   `GET /workouts/bulk/:id/status` serves the same fragment for the poll;
   `POST /workouts/bulk/:id/cancel` requests cancellation (a draft is
   cancelled immediately).

`parameters` holds `return_to` (a sanitized local path, so the review page can
offer a way back to the filtered list), the `sport_id` for a sport change, and
later the publishing choices. Item statuses are `queued`, `modified`,
`skipped`, `failed`, `cancelled`; a terminal item carries a translated
`failure_code` (`missing_original_file`, `reanalysis_failed`,
`workout_missing`, `unknown`), never a raw exception message. Operation
statuses are `draft`, `queued`, `processing`, `completed`, `failed`,
`cancelled`.

`WorkoutBulkOperationItem#workout_id` is nullified when the workout is deleted
(`ON DELETE SET NULL`), so a deletion operation survives its own effect and
still reports the outcome.

## 5. The job

`Workouts::BulkOperationJob` walks the queued items in `position` order,
25 per invocation, and re-enqueues itself while work remains
(`DERIVATIONS.md`). One operation per account runs at a time
(`limits_concurrency`). The job is resumable: a crash leaves queued items
queued and the next invocation continues; each item is applied through a
service that is idempotent for its operation (a sport already changed, a
workout already deleted). Cancellation is observed between items; remaining
queued items become `cancelled` and the operation ends `cancelled`.

An unexpected per-item error is reported through `Rails.error` and marks that
item `failed`; it never stops the batch. An unexpected job-level error marks
the operation `failed` and re-raises, mirroring `ImportBatchJob`.

## 6. Privacy and federation

- Quick actions and metadata changes never alter an existing publication; the
  review page repeats the §19.4 sentence for a sport change.
- Bulk deletion withdraws each publication through the same
  `Workouts::WorkoutDeletion` transaction as a single deletion, and the review
  page carries the mandatory §19.9 copy in its plural form.
- Each activity keeps its own publication identity: there is no grouped
  `Create` and no grouped `Delete`. One operation can therefore produce N
  federated activities.
- Nothing in this feature reads or writes another account's rows, and no
  federation vocabulary appears in the owner's UI.

## 7. UI

`DESIGN.md` §10.19 defines the selection component; §20.4 defines the review
and progress screens. In short:

- the table's first column is a checkbox (`d-none d-lg-table-cell`); its header
  cell is the tri-state page selector;
- a `card-header` bulk bar appears as soon as a row is checked (CSS `:has()`,
  enhanced by `bulk_selection_controller.js`). It carries the live count, the
  « Sélectionner les N activités filtrées » scope switch (absent when the page
  already contains the whole result, replaced by the cap hint above 500), the
  quick-action select and its button, and the review buttons;
- the bar is a plain form. Its checkboxes are associated by `form=` so the
  table markup stays intact; the quick button carries `name="_method"` and
  `value="patch"`, the review buttons carry `formaction` without it. The whole
  surface works without JavaScript; JavaScript adds the live count, the
  tri-state and the enablement of the buttons;
- the review and progress pages follow the existing card vocabulary and the
  import progress anatomy respectively.

## 8. Tests

- Request: owner scoping, foreign and malformed ids dropped, scope replay
  through `ListQuery`, cap refusal with nothing written, quick notices, the
  companion's HTML carrying no bulk markup, bulk markup absent from the card
  view.
- Model/job: draft freezing, one draft at a time, confirm validation, item
  statuses and failure codes, resumability, cancellation, deletion nullifying
  the item's workout while still reporting success.

## 9. Deferred

- Publishing operations: publish with a profile, withdraw, cancel a scheduled
  publication.
- The outbound volume cap those operations will need.
