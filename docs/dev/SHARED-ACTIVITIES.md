# Shared activities contract

A workout can be linked to a confirmed participant, and optionally credited to
them so that it also counts for that account. Two producers create the same
link: an explicit invitation by the workout owner, and an automatic co-presence
suggestion. This document defines the durable rows, the mutual-confirmation
contract, the credit/link distinction, the credited metric set, the local
attribution rules, the reduced federated contract, the detection algorithm, the
notification kinds and the surfaces. `DESIGN.md` governs the visual component
and the mandatory privacy copy; where the two conflict on a data or protocol
contract, this document wins.

## 1. Product decision

- A workout carries **participants**. A participant is an account the workout is
  linked to, after both sides confirmed: the owner proposed (or confirmed a
  detection) and the participant confirmed.
- A participation is either a **credit** or a **link**:
  - a *credit* means the participant has no recording of their own; the owner's
    workout counts for them;
  - a *link* means the participant owns their own recording of the same
    activity; the two workouts point at each other, both carry the « Avec @X »
    badge, and nothing is counted twice. Detection only ever produces links.
- Confirmation is **mutual and revocable**. Either side can withdraw. There is
  no third-party tagging: only the workout owner can propose, and only the
  invited account can confirm.
- A confirmed participant sees the workout's **credited metrics** (§5) on their
  own instance. Geometry (`route`, `chart`, `map`, `route_image`) follows the
  **owner's active publication policy**, never the confirmation alone. An
  unpublished source renders a metrics-only participant view with an
  explanatory hint (`DESIGN.md` §19).
- A workout is **never duplicated**: its track, original file, physiological
  channels and owner-only analysis never leave the owner's account. A confirmed
  credit gives the participant a **credit row**: a `Workout` row of their own
  that carries only the credited metric set, no geometry, and counts for them
  like any other activity. Its personal derived rows (best efforts, segment
  efforts) are computed from the source's points without ever copying them.
- Participant lists are **live social state**, never part of a publication
  snapshot or a sanitized representation, exactly like reactions
  (`REACTIONS.md`). They are not federated inside the Note in v1.

## 2. Why a credit row

A full copy of the workout for the participant is rejected: the owner of a row
reads its raw track everywhere — original download, track and chart endpoints,
REST `/track` and `/original`, MCP `include_geometry: raw`, segment creation —
so every surface would leak the source owner's route outside their privacy
zones and publication policy. A copy also breaks the unique source digest,
shares Active Storage blobs without reference counting, falsifies provenance,
and forces a bad deletion choice.

A reference-only relation over the owner's workout is rejected too: every
per-workout association would also return the participant's rows, so the
owner's analysis card, trophies, REST and MCP payloads would show them, and a
publication would carry the participant's record markers under the owner's
name.

The adopted design is a **credit row** owned by the participant, holding only
the credited metric set and no geometry. Because it is their row, every
existing read path counts it unchanged; because it has no track, no original
and no location, a surface that forgets it fails closed — an empty map, a 404,
a refused publish — never a leak. A credit row is never publishable, so shared
leaderboards exclude it by their existing publication gate.

## 3. Data model

### 3.1 `workout_participations`

| Column | Meaning |
|---|---|
| `workout_id` | the owner's workout, cascade |
| `participant_actor_id` | local or remote actor, per the `Reaction` precedent |
| `kind` | `credit` or `link`, default `credit` |
| `participant_workout_id` | the participant's own recording; required for `link`, forbidden for `credit` |
| `origin` | `invitation` or `detection`, default `invitation` |
| `owner_confirmed_at` | set when the owner proposes or confirms a detection |
| `participant_confirmed_at` | set when the participant confirms |
| `declined_at` | terminal refusal |
| `withdrawn_at` | termination after confirmation |
| `detector_version` | set for `detection` rows |
| `wire_activity_uri` | identity of the outbound `Invite` for a remote invitation |
| timestamps | Rails timestamps |

Checks:

- `origin` is `invitation` or `detection`; `kind` is `credit` or `link`;
- `(kind = 'link') = (participant_workout_id IS NOT NULL)`;
- `origin <> 'detection' OR kind = 'link'`;
- partial unique `(workout_id, participant_actor_id) WHERE withdrawn_at IS
  NULL`: at most one pending, confirmed or declined link per pair. A **decline
  is terminal for that pair on that workout**: the owner cannot re-propose
  after a refusal, which removes the re-invite spam vector. Only a withdrawal
  frees the pair for a fresh proposal;
- partial unique `(participant_workout_id) WHERE withdrawn_at IS NULL AND
  participant_workout_id IS NOT NULL`: one recording links to one source;
- the participant's actor cannot be the workout owner's actor; for a `link`,
  `participant_workout_id` must belong to the participant and must not be the
  source workout.

"Confirmed" is derived: `owner_confirmed_at.present? &&
participant_confirmed_at.present?`; no extra status column that could drift.
The manual invitation sets `owner_confirmed_at` immediately; a detection row
starts with both nullable and requires two confirmations. `owner_confirmed_at`
always names the source workout's owner, including for a detection, where that
owner confirms the symmetric suggestion.

Local participant identity is the actor; `Actor#user` resolves the account. A
tombstoned remote actor keeps its row and renders as a deleted account.
Detection rows carry `detector_version`, so a future re-tuning can re-evaluate
or backfill without guessing. Deleting either workout ends its participations
in the destroy transaction: the source's `before_destroy` detaches its credit
rows and withdraws the participation notices; the FK cascade then removes the
participation rows, which are live state and leave no history.

### 3.2 Credit rows on `workouts`

A credit row is a `Workout` owned by the participant that stands for a
confirmed `credit` participation. `workouts` gains:

| Column | Meaning |
|---|---|
| `origin` | `import` (a recording) or `credit`; `manual` is the typed entry |
| `credited_from_workout_id` | the source while attached, `ON DELETE NULLIFY` |
| `credited_by_actor_id` | the source owner, kept after detachment for the badge |
| `credit_detached_at` | set when the source was deleted |
| `credited_max_climb` | the ascent of the source's biggest detected climb, for the `MC` record |

For credit rows only, `start_point`, `bounds`, `points_count` and
`import_format` are nullable. Checks:

- `workouts_origin`: `origin IN ('import', 'credit', 'manual')`;
- `workouts_recording_shape`: a recording has `points_count` and
  `import_format`, and has both `start_point` and `bounds` or neither (a
  positionless recording has no location, `[devdoc:no-gps]`), while a credit
  row has none of the four;
- `workouts_credit_shape`: an import implies the credit columns are NULL; a
  credit implies `credited_by_actor_id IS NOT NULL`, `credited_from_workout_id
  IS NULL OR credit_detached_at IS NULL`, and every excluded column is empty:
  `source_digest`, `import_connection_id`, `external_id`, `source`,
  `description`, `notes`, `calories`, the six physiological columns,
  `grade_adjusted_pace`, `min_elevation`, `max_elevation`, `weather_start`,
  `weather_end`; `commute` false; `places` `[]`; `data_anomalies` `{}`;
- partial unique `(credited_from_workout_id, user_id) WHERE
  credited_from_workout_id IS NOT NULL`: one credit row per participant and
  source;
- index `(user_id, credited_by_actor_id, started_at) WHERE origin = 'credit'`
  for the re-attachment lookup.

`Workout` mirrors the checks: presence of the location columns and the
`import_format` inclusion only `if: :recording?`; `credit?`/`recording?`/
`credit_detached?` predicates and the `recordings`/`credit_rows_only` scopes;
`belongs_to :credited_from, optional`, `belongs_to :credited_by`,
`has_many :credit_rows, foreign_key: :credited_from_workout_id`. The row keeps
the ShortUUID identity of any workout.

**Column contract.** While attached, `Participations::CreditSync` owns these
columns and copies them from the source: `sport_id`, `started_at`, `duration`,
`moving_time`, `pause_time`, `distance`, `ascent`, `descent`, `average_speed`,
`average_pace`, `max_speed`, `best_pace`, `title`, `elevation_filter`,
`analysis_version` and `contested_metrics` (records must skip a figure the
source's anomalies contest; never displayed on a credit row), plus
`credited_max_climb`, derived as the largest `ascent` of the source's detected
climbs when the sport records elevation. Nothing else is ever copied.

**Derived rows.** No unique key changes. `best_efforts` and `segment_efforts`
rows of a credit row carry `workout_id` = the credit row and `user_id` = the
participant, so the existing keys already separate athletes, and
`records`/`effort_records` point at the participant's own row. **Kinematics
only**: heart rate, cadence and power are NULL on a credit row's segment
efforts; best efforts carry none. A credit row has no `track_segments`, `laps`,
`detected_laps`, toponymy, place names, elevation cache, route image, original
file, publication, auto-publication, equipment, comment, reaction or
participation of its own. Only `credit` participations produce a credit row;
`link` rows produce none.

### 3.3 `remote_participations`

One row per invitation a local account received from another instance's owner:

| Column | Meaning |
|---|---|
| `remote_note_id` | the received note the invitation rides on |
| `actor_id` | the inviting owner's remote actor |
| `recipient_actor_id` | the local invited actor |
| `status` | `pending`, `accepted`, `rejected`, `withdrawn` |
| `sport_slug`, `started_at` | the Invite's own values |
| `invite_uri` | the Invite identity |
| `credit_workout_id` | the credit row built on confirmation |
| timestamps | Rails timestamps |

Unique `(remote_note_id, recipient_actor_id)`. A refusal is terminal for that
note. The row is live state and never enters a publication snapshot.

## 4. Authorization and visibility

- Only a signed-in workout owner can propose a local participation; only the
  invited account can confirm or decline; either side can withdraw a pending or
  confirmed link. Denial is 404, never 403.
- **Invitation gate.** A local invitation requires an accepted follow in at
  least one direction between the two accounts, the same relationship the
  remote contract requires. Anyone else cannot be invited, so an invitation
  can never disclose an unpublished workout's title to an unrelated account.
- The participant's view of the source workout is:
  - the credited metric set and the participant list for every active
    participation — pending or confirmed. A pending invitee deliberately
    already reads the metrics-only presentation: they need the page for the
    confirm/decline card, and the invitation gate bounds who can be invited;
  - geometry only through the owner's active `Workouts::PublicationPolicy`, as
    if the participant were any other reader;
  - no publication: a dedicated metrics-only participant presentation. The
    owner's source track is never rendered. Once the source is published, the
    participant reads the standard publication presentation as any reader — a
    metric the owner's profile masks may be absent there while the credited set
    keeps it, and the credit row shows the full credited set.
- **Leaderboards.** A credited effort is a segment effort whose workout is a
  credit row. Every ranked read goes through `Segments::Listing`, which admits
  an effort only through an active publication of its own workout; a credit row
  is never publishable, so boards, standings, podiums, sections, the board
  preview and the segment index's record column exclude it without a change.
  Two counters read `segment_efforts` directly and must join `workouts` and
  keep `origin = 'import'`: `Segment#participants_count` and `athletes_count`
  in `Segments::MatchWorkoutJob#refresh_segment`. `Segments::Reach` reports a
  credited effort as not ranked, with its own reason. The owner's publication
  is the owner's consent, not the participant's. Credited efforts still feed
  the participant's personal bests, personal places, effort history, `/records`
  and the credit row's Analysis card.
- Account deletion withdraws the account's live participations as participant,
  through `Users::DeleteAccount`; as source owner, each deleted workout
  detaches its credit rows and withdraws the open notices. Blocking and remote
  unfollow do the same for remote participations. **Suspension is not a
  withdrawal**: it only revokes access, and a reinstated account finds its
  participations intact.
- Detection never compares, and never mentions, an account pair without an
  accepted mutual follow, and respects `users.together_detection_enabled`.

## 5. Credited metric set

The credited metric set is fixed and kinematic: sport, `started_at`,
`distance`, `moving_time`, `elapsed_time` (duration), `ascent`, `descent`,
`average_speed`, `average_pace`, `max_speed`, `best_pace`, and the title. It is
the only set a participant ever reads from a source workout, the only set a
credit row stores and therefore the only set aggregates can sum, and the only
set the metrics-only participant presentation renders.

Excluded, everywhere a credit is read: heart rate, cadence, power, calories,
weight-derived values, description and notes, the recording device, the
`commute` flag, geocoded places and the pin line, weather, detected laps and
toponymy. `Stats::Aggregates` sums `calories` straight from `workouts`; the
exclusion holds because the credit row never stores the excluded columns, not
because a view hides them.

## 6. Local write seams

One service per transition, each the single write seam for its effect:

- `Participations::Propose` (owner): resolves the target through
  `Federation::TargetResolver`, refuses self, blocked actors, accounts outside
  the invitation gate, a pair already declined on this workout, and
  unpublished-for-remote cases; creates the pending row as a `credit` with
  `owner_confirmed_at` (the owner cannot know whether the participant recorded
  the activity), and notifies the participant.
- `Participations::Decide` (participant): confirms or declines; confirming may
  switch a proposed `credit` to a `link` by naming the participant's own
  recording (a recording, never a credit row), sets
  `participant_confirmed_at`, notifies the owner, and enqueues
  `Participations::CreditJob` after commit for a `credit`; declining sets
  `declined_at` and withdraws the request notification.
- `Participations::Convert` (participant): turns a confirmed `credit` into a
  `link` by naming the participant's own recording, later than the original
  decision; in one transaction it sets the link and destroys the credit row
  (its destroy callbacks recompute the participant's records; its derived rows
  cascade). The participation stays confirmed, so no notice is sent: the owner
  reads the new kind on the card.
- `Participations::RecordingRules` is the one rule for a nameable recording,
  shared by `Decide` and `Convert`: the participant's own, not the source, not
  already in a live link. Its `candidates` feed the picker: recordings starting
  within six hours of the source, closest first, at most ten.
- `Participations::Withdraw` (either side): sets `withdrawn_at`, destroys the
  attached credit row if any, and withdraws open notifications.
- `Participations::CreditJob`: for a confirmed `credit`, creates or re-attaches
  the credit row through `Participations::CreditRows.attach` and runs
  `Participations::CreditSync`, idempotently per `(source workout,
  participant)`; a `link`, a withdrawn or a no-longer-confirmed participation
  is a no-op.

Each service commits its row (and its outbox intent, remote only) first; the
notification is created after the commit and never raises, so the gesture and
its notice both hold even if the process dies between the two. Expansion is
enqueued after commit, and a queue failure never rolls the gesture back.

## 7. Local attribution of credits

### 7.1 Creation and synchronization

`Participations::CreditJob` creates or re-attaches the row and runs
`Participations::CreditSync`. The sync copies the column contract only, follows
a re-analysis, a sport change or a title edit of the source, and stamps
`credited_max_climb` from the source's detected climbs. It is idempotent per
`(source workout, participant)`. The participant's own deletion withdraws the
participation and is never undone by a late job.

### 7.2 Derived rows

`BestEfforts::Rebuild` and `Segments::MatchWorkoutJob` read the **source's**
points and write rows on the credit row with the participant's `user_id`. The
participant's private segments match their credit rows. No routes, loops or
laps are derived. Physiological channels are NULL. A credit row's biggest climb
is a number only; it wins the participant's `MC` record when larger, follows a
source climb rebuild, and survives detachment.

### 7.3 Segment counters and refresh

Deleting any workout refreshes `efforts_count`, `athletes_count` and moves the
`personal_best` flag to the next best effort (`Segments::Refresh`). A segment
update keeps a detached credit row's efforts on a tolerance change and drops
them on deactivation or an excluding sport. Credited efforts never appear in
the shared board counters.

### 7.4 Deletion and detachment

Deleting the source detaches the participant's credit row and keeps it as a
frozen, metrics-only activity without the owner's title: figures, efforts and
records survive, the title is dropped, and the `participation_source_deleted`
notice is created. Later sweeps and matcher runs leave the frozen row
untouched. The same owner's re-imported activity within ±120 s re-attaches it
instead of counting the outing twice. A remote credit is detached only by that
instant, because it never has a local source.

### 7.5 Guards and exclusions

A credit row is not a recording: the owner actions that assume a track answer
404 or `credited_workout`, and the sweeps that assume a recording never select
one. The remote-import near-duplicate check imports the participant's own
recording. Instance metrics count an outing once. A credit counts once in
`Stats::Aggregates`, `/me` and the seven column records, and contributes no
calories.

## 8. Reduced remote contract

A remote participation is always a credit: the wire has no way to name the
participant's own recording, and a link would count nothing.

### 8.1 Preconditions

`Participations::Propose` resolves the handle. An unresolvable handle,
including one the outbound guard refuses, is a refusal and never an error. It
invites a remote account only when:

- the account **holds the publication**: the narrowest active publication of
  the workout whose `Create` authorized that account and is live (pending,
  delivering or delivered). The invitation rides on that publication. This is a
  privacy rule and a transport rule: a secondary event reaches only the
  recipients of its `Create`;
- the account **follows the owner** (an accepted follow);
- the publication **shares the credited figures**
  (`Propose::REMOTE_REQUIRED_METRICS`): distance, duration, moving time,
  ascent, descent and average speed. A remote credit row is built from them,
  and the `workouts` NOT NULL columns stay as they are.

A followers-only publication can carry an invitation only while
`FEDERATION_RESTRICTED_ENABLED` lets it reach a promoted peer. The owner's alert
for a refused remote handle names these conditions (`DESIGN.md` §19.20).

### 8.2 Wire contract

| Direction | Activity | Identity | Addressing |
|---|---|---|---|
| owner → invited | `Invite` | minted by the owner actor's URI, key `participation:invite:<participation uuid>`, stored in `workout_participations.wire_activity_uri` | `to: [invited]` |
| invited → owner | `Accept` / `Reject` of the Invite | invited actor, key `participation:accept\|reject:<invite uri>` | `to: [owner]` |
| invited → owner | `Undo` of its `Accept` (`object.object` = the Invite) | key `participation:undo-accept:<invite uri>` | `to: [owner]` |
| owner → invited | `Undo` of the Invite | key `participation:undo-invite:<participation uuid>` | where the Invite was attempted |

The `Invite` is `{type: "Invite", actor, object: <publication object_uri>,
target: <invited actor>, _allure_participation: {sport_slug, started_at}}`. It
carries no metric and no geometry. The receiver reads the figures from the note
it holds; the slug and start travel because the note carries only a localized
sport label. `Invite` is the ActivityStreams semantics ("the actor is extending
an invitation for the object to the target"). `Join` is not, because its object
is a Group.

### 8.3 Transport

The `Invite` is a **secondary publication event**, like the comment relay's
`Announce` (`COMMENTS.md`). It sits beside `Create` and `Announce` in the
recipient authorizer, the expander's waiting and cancelling branches, the
delivery's sendability and predecessor rules, the live-publication scope and
the publication preflight. As a result, it reaches only an account that holds
the publication, waits for the `Create` to reach that account, and stops with a
withdrawn or replaced publication. The owner's `Undo` goes only where the
Invite was attempted. An Invite that never left is cancelled instead. The
answers are ordinary `Actor`-subject activities of the invited account.

### 8.4 Receipt

On the invited instance, `Federation::Inbox::ParticipationInvite` stores a
pending `RemoteParticipation` only when all of these hold:

- the `target` is a local account;
- the object is the sender's own active note;
- the account holds an active entitlement to that note. Reading a public note
  is not enough;
- the account still follows the sender. An entitlement is only granted to a
  follower, and this keeps an invitation from outliving the follow it rests on.

It keeps the slug and the start only when they are well formed. It is
idempotent by the Invite's identity, keeps one live row per account and
publication, and never re-offers a refused publication. The Invite carries the
publication's own sport slug and start, never the live workout's.

Two receipt cases need care:

- **The Invite arrives before its note.** The inbox processes the `Create`
  asynchronously, so the Invite can overtake it. If the note is unknown and the
  account follows the sender, the item retries instead of being rejected.
- **A new Invite for a pending invitation.** The owner withdrew and invited
  again. The new Invite takes over the row, so a late `Undo` of the old one
  misses it. The `participation_requested` notice names the note and opens it.

On the owner's instance, `Federation::Inbox::ParticipationAnswer` resolves an
answer from the Invite it names. The processor consults it before its follow
and comment readings. Only the invited account may answer: an `Accept` confirms
and sends the owner `participation_confirmed`; a `Reject` is terminal; an
`Undo` of the `Accept` withdraws. On the invited instance, only the inviting
owner's `Undo` of the Invite closes the row.

### 8.5 The invited account

The received note carries an « Activité partagée » card (`DESIGN.md` §10.18),
backed by `RemoteParticipationsController` and `Participations::RemoteAnswer`.
It offers Confirmer / Refuser while the invitation is pending, then Retirer.

Confirming gives the account a credit row (`Participations::RemoteCreditRows`):

- `origin: "credit"` and `credited_by` the owner's actor;
- `remote_participation_id`, unique; the `workouts_remote_credit_shape` check
  keeps it on credits with no local source;
- the required figures, plus maximum speed and average and best pace when the
  note shares them;
- the sport from the Invite's slug, else from the note's label;
- the start from the Invite, else from the note.

The row commits in the same transaction as the confirmation and its `Accept`,
so an error building it fails the confirmation too. If a figure is missing
(only a peer breaking the precondition sends that), the confirmation stands and
no row is built. The row counts in statistics and in the seven column records.
It has no best effort, segment effort or biggest climb, because the received
track has no timestamps or sensor channels; this is a deliberate limit. Its
page and card take the received note's map and route image while the account
may read the note, and the badge links to the note.

### 8.6 Lifecycle

The row and its credit end in these cases (`Participations::RemoteWithdrawal`):

- **the account withdraws**: the account's own Retirer, or deleting the credit
  row. The owner hears through an `Undo` of the `Accept`, except during the
  account's own deletion, whose actor `Delete` tells the owner instead;
- **the owner withdraws**: the owner's `Undo` of the Invite;
- **an unfollow or a refused follow**: the owner hears of a confirmation taken
  back;
- **a block**: participations end in both directions, and nobody is told;
- **the invited account's deletion**: its actor `Delete` tells the owners.

An attached credit row goes with its participation. A credit already detached
is kept for a later invitation to re-attach.

On the owner's instance, the peer closes some invitations without answering, so
the owner's rows close too:

- a pending invitation whose publication left;
- every invitation of a participant whose `Undo(Follow)` arrives.

Inviting again replaces a row that rides on a publication that is gone. A
refusal stays terminal: an owner's `Undo` of a refused Invite changes nothing. A
double confirmation answers once, because the row is locked.

**Deletion or republishing.** A note or author `Delete` closes a pending
invitation. A confirmed one stays: its credit is detached and kept
(`credit_detached_at`, the owner's title dropped,
`participation_source_deleted`). A remote credit is detached only by that
instant, because it never has a local source. Republishing tombstones the old
note, so the credit detaches. A new invitation on the new publication, for the
same owner's outing within ±120 s, re-attaches the same row instead of counting
the outing twice.

On the owner's side, a participant's author `Delete` withdraws the
participations naming it. Confirmed remote participants render on the owner's
workout as live state, never in a snapshot.

### 8.7 Other surfaces

- **Webhooks.** `participation.requested` and `participation.confirmed` carry
  `remote_note_id` instead of `workout_id` for an invitation received from
  another instance.
- **Notifications.** A failed webhook emission does not cost the in-app notice:
  `Notifications::Create` rescues the emission separately.
- **Ring gate.** `dip fed_test` proves the whole path: the Invite addressed to
  the receiver alone and carrying no geometry, its receipt and card, the
  confirmation with its credit row and `Accept`, the owner's confirmed row, and
  the credit detached after the publication's `Delete`.

## 9. Automatic co-presence detection

A detection is a producer of the same pending row; it never confirms anything
by itself, and it only produces **links**: a co-presence match needs two
recordings, so both accounts already own a workout and nothing may be credited
twice.

- **Algorithm**: `Allure::Together::Detector` under `lib/allure/together/`,
  versioned like `Allure::Segments::Matcher#VERSION`. It rebuilds absolute
  times and distances with `Allure::Segments::PointStream` and computes
  geodesic distances with `Allure::Gpx::Geo`. It samples the shared window
  every 15 s with one forward cursor per recording, interpolating a position
  only between points at most 120 s apart (an unknown position counts against
  the match). A pair matches when:
  - both workouts belong to the same sport family
    (`Allure::Together::SportFamilies`: the per-account default families
    cycling, running and walking without their virtual members, every other
    sport on its own; a virtual sport never matches) and neither is `commute`;
  - their recording windows overlap by at least the minimum overlap (20
    minutes, or 50 % of the shorter moving time when that is less);
  - a time-ordered merge finds samples within a time gap (120 s) where the
    interpolated positions are within the distance threshold (60 m);
  - the matched fraction of the shared window is at least the match ratio
    (default 80 %).

  Thresholds are constants in the detector, tuned with synthetic specs, never
  hardcoded in jobs.
- **Row orientation**: the earlier-imported workout is the source and the later
  one is `participant_workout_id`; the orientation carries no meaning, both
  accounts see a symmetric suggestion. When the later recording is already
  linked elsewhere (one recording links to one source), the reverse orientation
  is used, else nothing is suggested.
- **Known pairs**: `Together::Detection` never suggests a pair a participation
  already names, in any state and either orientation, nor a pair with a
  participation between one workout and the other's account: a refusal or a
  withdrawal stays the last word, and a credit is the credit-to-link
  suggestion's business.
- **Answering**: each side answers for itself through `Participations::Decide`
  (the source owner may now answer a detection), and each confirmation sends
  the other side `participation_confirmed`. A pending detection never opens the
  counterpart's workout: `set_workout_for_show` admits a detection's
  participant only once both confirmed, the counterpart answers from their own
  recording's participants card (which also lists the links naming it), and the
  participation notice opens the recipient's own recording. Answers return to
  the page they came from.
- **Candidates**: `Together::CandidateQuery` prefilters with the time window
  (`started_at ± (duration + margin)`) and `ST_DWithin` on
  `track_segments.geom` / `workouts.start_point`, the same pattern as
  `Segments::CandidateQuery`. A global `started_at` index on recordings and a
  spatial prefilter ("the two tracks pass within 200 m of each other
  somewhere") also catch a partner who joined mid-ride.
- **Privacy rules**: detection only compares workouts of accounts with an
  accepted **mutual** follow, only when both accounts enabled
  `users.together_detection_enabled` (switch at `/settings/notifications`, on by
  default), and only for local accounts. A match creates a `detection` link row
  that requires both confirmations; both accounts receive the same
  `participation_suggested` notification at the same time, so neither learns
  anything before the other can also see the suggestion. The suggestion
  discloses the counterpart's workout title and date to a mutual follower who
  was there; it never discloses a location, a distance or the match score.
  Known false positives are mass events and popular loops; the confirmation
  gate and the withdrawal are the remedy, and v1 publishes no score or reason.
- **Run points**: after import (`Together::DetectWorkoutJob`, queued after
  commit, bounded to the mutual-follow set) and via an audited backfill at
  `/admin/jobs` (`Together::BackfillDetectionJob` over the recordings whose
  `workouts.together_detection_version` is below the detector's version, which
  every detection run stamps; [DERIVATIONS.md](DERIVATIONS.md)).
- **Cost guardrail**: the detector stays linear in points with a sliding merge;
  no O(n²) scan of segments, one candidate pass per workout pair.
- **Credit-to-link suggestion**: when the participant imports their own
  recording of an outing they hold an attached credit row for, the detector
  compares it with the credit's source (same time AND same place, never a
  start-time window alone, which would suggest the wrong recording on a day
  with two outings) and, on a match, suggests converting the credit into a
  link: a notice and a banner on both pages, one click through
  `Participations::Convert`, and a per-pair dismissal. The double count lasts
  until the participant converts. `Together::CreditLinkSuggestion` runs with
  each import's detection and after `CreditJob`; it reads only the
  participant's own detection switch, since the comparison discloses nothing.
  The suggestion lives on the participation (`suggested_workout_id`, nullified
  with the recording, and `link_suggestion_dismissed_at`; a check keeps it on
  credits), the participant gets the actorless `participation_link_suggested`
  notice opening their recording, and the banner sits on that recording and on
  the credit row page. Conversion clears it; « Ignorer » closes it for good.

## 10. Notifications

Four kinds, added with the notifications contract's recipe (extend
`Notification::KINDS`, the database check constraint, `PREFERENCES`, a user
preference column, settings switch, both locales, helper text and target):

| Kind | Recipient | Actor | Created when |
|---|---|---|---|
| `participation_requested` | the invited account | the owner | a manual invitation waits for the participant |
| `participation_suggested` | both accounts | the counterpart | a detection row waits for both confirmations; each side's copy targets its own confirm action |
| `participation_confirmed` | the owner (invitation) or the counterpart (detection) | the confirming account | the participant confirms an invitation; for a detection, each confirmation notifies the other side |
| `participation_source_deleted` | the credited participant | none | the source of an attached credit row was deleted and the row detached; the subject is the participant's credit row |

Per-account switches `users.notify_participation_requests` (requests and
suggestions) and `users.notify_participation_confirmed` (confirmations and
source deletions), on by default. Withdrawn on decline, withdrawal, block,
unfollow, account deletion, and source or counterpart workout deletion, through
`Notifications::Withdraw`. Copy is sober: it names the workout title and the
account, never a location, a distance or a detection score.

## 11. Surfaces

- **Workout page (owner)**: a participants card in the full-width region next
  to the publication cards. It lists pending and confirmed participants with
  their avatars, handles and kind (credit or link), the add-by-handle field
  (limited to the invitation gate), the per-row remove action, and the confirm
  action for detection suggestions. The card is never rendered to visitors.
- **Workout page (confirmed participant)**: the metrics-only participant
  presentation when the source is unpublished; the standard publication
  presentation when it is viewable. The header carries the « Avec @X » badge. A
  linked participant's own workout page carries the same badge pointing at the
  counterpart, and the convert-to-link action for a credit. A tombstoned
  account renders as a deleted account, without a handle, everywhere a
  participation names it.
- **Credit row page**: the participant's own `/workouts/:id` for a credit row,
  rendered by `workouts/credit`. Header: the source title (or the generated
  title once detached), sport, date, and the « Avec @X » badge, linking to the
  source page while the participant may still open it, reading « activité
  source supprimée » once detached. Body: the credited metric summary, without
  the « not recorded » list for the excluded channels; the Analysis card
  limited to its Segments and « Meilleurs efforts » tabs; the convert-to-link
  action while attached. The map is the source's, served through the
  publication the participant may read, never the raw track; without a readable
  publication a line says the route stays governed by its owner's profile, and
  once detached that it is gone. The `⋯` menu holds only « Retirer de mes
  activités » (the deletion, which withdraws the participation). No profile
  chart, no publications, comments, reactions or participants card.
- **Lists**: a credit row is the participant's activity, so it appears in their
  `/workouts` list, table view, `/me` recent cards and every stat, with the
  « Avec @X » badge and the source publication's route image when the
  participant may read it; otherwise no image area and no pending skeleton. The
  owner controls a credit row lacks are hidden per row: it is not selectable in
  the bulk table, and has no place to filter on. `/me/records` and the effort
  history link to it. The profile and the feed never show it: it is never
  published.
- **REST, MCP, webhooks**: `WorkoutSerializer` gains `origin`
  (`import`/`credit`) and `credit`, `null` on a recording and
  `{ recorded_by: Account, source_deleted }` on a credit row (the account that
  recorded it, never the source's id). On a credit row `import` and
  `import_format` are `null` and `links` carries only `self` and `web`.
  `docs/openapi/v1.yaml` follows, under its contract specs. Webhook payloads
  reuse the serializer; the MCP workout summary adds `origin`.
- **Remote note page**: a pending invitation card with confirm/decline, then a
  credited card, gated by the note's entitlement.
- **`/settings/notifications`**: the two switches plus the detection opt-out.
- `DESIGN.md` gains the anatomy of the participants card, the badge, the
  participant presentation, the empty state, and the mandatory privacy copy for
  detection and for remote credit.

## 12. Tests

- **Model**: unique active pair, decline blocks re-proposal, no
  self-participation, link requires and credit forbids
  `participant_workout_id`, detection is always a link, derived confirmation.
- **Services**: `Propose`/`Decide`/`Withdraw` authorization and transitions
  including the invitation gate; notification producers and withdrawals;
  request specs (404 outside the pair, Turbo confirmation, participant
  presentation limited to the credited metric set and without geometry).
- **Credit rows**: `workouts_recording_shape` and `workouts_credit_shape`
  reject a half-cleared recording, a credit row with any excluded column, a
  detached row with a source, and a second attached credit row per participant
  and source; confirmation creates exactly one credit row (idempotent job); the
  sync copies the column contract only (a spec enumerates the copied and the
  never-copied columns); a re-analysis, sport change or title edit of the
  source reaches the credit row; withdrawal and conversion destroy it and
  recompute the participant's records; the participant's deletion withdraws the
  participation and is never undone by a late job.
- **Detachment**: through both `WorkoutDeletion` and `Users::DeleteAccount`,
  figures, efforts and records survive, the title is dropped, the
  `participation_source_deleted` notice is created, and later sweeps and
  matcher runs leave the frozen row untouched; re-attachment on a re-imported
  source within ±120 s, no second row.
- **Derived rows**: best efforts and segment efforts computed from the source's
  points with the participant's `user_id` and NULL physiological fields; the
  participant's private segments match their credit rows; no routes, loops or
  laps on a credit row.
- **Privacy negatives**: the owner's records, Analysis card, publication
  snapshot (`record_types`/`record_distances`), REST, MCP and webhooks contain
  nothing of the participant; the participant's REST, MCP and webhook payloads
  contain no source id, coordinate, physiological value, device, place or
  description.
- **Leaderboards**: credited efforts absent from `Segments::Listing` consumers,
  `participants_count` and `athletes_count`; the reach reason.
- **Segment refresh**: deleting any workout refreshes `efforts_count`,
  `athletes_count` and moves the `personal_best` flag to the next best effort;
  `Segments::Updater` keeps a detached credit row's efforts on a tolerance
  change and drops them on deactivation or an excluding sport.
- **`MC`**: a credit's `credited_max_climb` wins the participant's
  biggest-climb record when larger, follows a source climb rebuild, and
  survives detachment; the owner's `MC` is unchanged.
- **Guards**: every owner action on a credit row answers 404 or
  `credited_workout`, the sweeps never select one, `near_duplicate` imports the
  participant's own recording, instance metrics count an outing once.
- **Stats**: a credit counts once in `Stats::Aggregates`, `/me` and the seven
  column records, and contributes no calories.
- **Detection**: detector unit specs on synthetic tracks (match, no match on
  time, no match on distance, partial overlap, commute exclusion, loop false
  positive), candidate prefilter bounds, detection requires mutual follow and
  opt-in, detection rows are links and never credit, symmetric suggestion
  notifications, backfill idempotency.
- **Remote**: the Invite's identity, addressing and absence of figures;
  delivery only to an account holding the publication, never after its
  withdrawal; receipt bounded by the entitlement, idempotent, with a refusal
  terminal; Accept/Reject/Undo on both sides, the owner's Undo or cancellation,
  and the unfollow, block and Delete cascades; the remote credit row and its
  detach and re-attach; the `dip fed_test` phases for invitation, card,
  confirmation and detachment.
- Every change runs `dip rspec`, `dip rubocop` and `dip brakeman`; UI changes
  are verified in the browser.

## 13. Out of scope

- A copy of the source's track, original file, physiological channels or
  owner-only analysis in any form; the credit row holds the credited metric set
  only.
- Credit rows for links, equipment totals, and detected laps or named climbs
  from a credit; the biggest climb is credited as a number only.
- Re-deriving a detached credit row's efforts after a matcher change, or
  restoring them after a segment deactivation.
- Participant lists inside publication snapshots, the `WorkoutNote` wire
  format, or `RemoteNote` representations; federation of who participated.
- Ranking a credited effort on a shared leaderboard (deferred to its own lot
  with a participant-level switch).
- Best efforts, segment efforts, records and detected laps for remote
  participants; the sanitized track cannot produce them.
- Physiological data of any kind on a credited row.
- Participant self-service beyond invitation and confirmation: no open "I was
  there" claim on someone else's workout.
- Automatic conversion of a credit into a link when the participant imports
  their own recording later; v1 offers the manual conversion and a suggestion,
  never an automatic conversion.
- Equipment attribution, place attribution, training-group or event models,
  comments, mentions, rankings between participants, and live count fan-out.
- Email, push, digests and metrics for participations.
