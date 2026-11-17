# People contract

The `/people` relationship hub, its opt-in directory, the name search, and the
suggestions that help a member find the accounts they already have a reason to
follow. `DESIGN.md` governs the visuals; where the two conflict on a data or
protocol contract, this document wins.

## 1. Product decision

The instance has no public directory. An account is findable by name only if
its owner has opted in, and even then a result shows the minimum needed to
recognize and follow someone: avatar, display name, handle, the viewer's
relationship, and the follow control. A hidden account remains reachable by
its exact handle, because following someone requires a way to name them.

The ActivityPub followers and following collections stay empty
(`Federation::Serializers::OrderedCollection`), so the follow graph is not
exposed through them. Nothing in this contract changes that.

## 2. Discoverability

`users.discoverable` is a string, `none` or `members`, defaulting to `none`
for every account, existing and new. It is set on `/settings/profile`, beside
the profile-sharing audiences, and never federates.

- `none`: the account never appears in name search or suggestions. Its exact
  handle still resolves.
- `members`: the account may appear in search and suggestions for any signed-in
  member of this instance.

A suspended account, an account in its deletion window, and a tombstoned actor
are never discoverable, whatever the column says (`User.discoverable` scope and
`User#discoverable?`).

The choice is exported in `account.json` under `preferences.discoverable` and
returned by `GET /api/rest/v1/me`.

## 3. Name search

`GET /people/search?q=` returns an HTML fragment for the search box's dropdown
(`People::Search`). The field itself remains a plain text input in the resolve
form, so without JavaScript it still submits an exact handle.

### 3.1 Matching

- At least three characters (`People::Search::MIN_QUERY_LENGTH`), at most eight
  results (`LIMIT`), no pagination and no "more results" affordance.
- Prefix match only, case- and accent-insensitive, on the username or the
  display name. A substring search would let a visitor walk a name from the
  inside.
- Local candidates are the discoverable members of this instance, excluding the
  viewer. The scan is bounded (`SCAN_LIMIT`); the endpoint is rate limited to
  30 requests per minute per account (`rate_limit`).
- Remote candidates are only the actors the viewer already has a live
  relationship with (accepted or pending, in either direction). The remote
  actor cache is never searchable, and the remote pass is skipped while
  federation is off. Blocked actors are removed with `Federation::Safety::
  Blocks.blocked_uris`.

### 3.2 What a result carries

`People::Search::Result` exposes the local user or the remote actor, the
viewer's outgoing Follow row, and the incoming Follow row. The view renders:

- the avatar (the account's chain for a local actor, the cached copy for a
  remote one);
- the display name and the handle;
- one relationship badge: following, request sent, follows you, or request
  received;
- the existing follow button.

No biography, place, sport, statistic, activity, follower count, or "last
active" is ever part of a result. The partial is the whole contract.

## 4. Suggestions

`People::Suggestions` offers at most five accounts, each with the reason it is
offered. Every signal comes from something the viewer can already see:

| Reason | Signal |
|---|---|
| `together` | a `WorkoutParticipation` the instance detected as done together |
| `interaction` | a reaction or a comment on one of the viewer's workouts |
| `leaderboard` | another athlete on a course the viewer has ridden |

An account is never suggested when it is the viewer, already followed or
invited, dismissed, tombstoned, blocked, or — for a local account — not
discoverable. The interaction window is 90 days; the leaderboard window is 180
days and the candidates are the ten athletes sharing the most courses.

`people_suggestion_dismissals` is one row per `(user, actor)` and is permanent.
`DELETE /people/suggestions/:id` creates it; the suggestion card never shows
that account again.

Deliberately absent: friends of friends (which would reveal the follow graph),
geographic proximity (which would reveal where someone lives or trains), and
"popular accounts".

## 5. The hub and removing a follower

`/people` keeps its four relationships but presents them as tabs:
**Following**, **Followers**, **Requests** (incoming and outgoing), each with
its count. Following and followers paginate through Pagy; incoming requests
paginate; outgoing requests are shown beside them.

The followed account may end one accepted follow with
`DELETE /people/followers/:id` (`People::FollowersController`,
`Federation::RemoveFollower`):

- a local follower: the row is undone, with no wire activity;
- a remote follower: the row is undone and a signed `Reject` of the Follow is
  delivered, as ActivityPub software expects;
- nothing is recalled from the follower's instance. Every later signed object
  and media GET is reauthorized here against the live follow, so the withdrawal
  is effective at the next read.

The row is scoped to the current account's local actor: another account's
follower answers 404. The action asks for confirmation through the shared
destructive modal and states the consequence (followers-only publications are
no longer served; a new request is possible).

## 6. Routes

| Route | Purpose |
|---|---|
| `GET /people` | relationship hub, `?tab=following\|followers\|requests` |
| `GET /people/search?q=` | name-search fragment (HTML, `no-store`) |
| `POST /people/resolve` | exact handle or actor URI (unchanged) |
| `PATCH /people/follows/:id` | accept or reject an inbound request (unchanged) |
| `DELETE /people/followers/:id` | remove an accepted follower |
| `DELETE /people/suggestions/:id` | dismiss a suggestion permanently |

## 7. Data model

```text
users.discoverable                     string, 'none' | 'members', default 'none'
people_suggestion_dismissals           user_id, actor_id, unique per pair
```

Both migrations carry their check constraint or unique index. No other table
changes: the search and the suggestions are read-only projections of existing
rows.

## 8. Copy and help

The discoverability choice and its consequence are stated in
`DESIGN.md` §19.39. The `/people` page and `/settings/profile` carry the same
sentence in every locale. The `sharing-beyond` help page explains that name
search is opt-in, that an exact handle always works, and that the follow graph
is not exposed through the ActivityPub collections.

## 9. Tests

- `spec/services/people/search_spec.rb`: prefix and accent matching, hidden,
  suspended and deletion-scheduled accounts excluded, the viewer excluded, the
  three-character minimum, the result cap, relationship flags, remote search
  limited to existing relationships, blocked actors excluded, federation off.
- `spec/services/people/suggestions_spec.rb`: the three signals, the
  discoverability gate, the viewer, already-followed, dismissed, blocked, and
  the time window.
- `spec/requests/people_spec.rb`: the search fragment and its `no-store`
  header, no biography in a result, removing a local and a remote follower
  (with the `Reject` payload), another account's follower is a 404, dismissing
  a suggestion.
- `spec/requests/settings_profiles_spec.rb`: the radio group, the default, the
  save, and the refusal of an unknown value.
- `spec/services/users/export_archive_spec.rb`: `discoverable` in the export.

## 10. Out of scope

- Personal block and mute: they touch the feed, comments, reactions,
  participations and federation, and get their own contract.
- Search in the REST API, MCP, or the iOS companion's own screens: the hub is
  the web surface; the companion reads it through the existing web view.
- Federated discovery of accounts the viewer has no relationship with.
