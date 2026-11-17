# MCP contract

Allure serves a [Model Context Protocol](https://modelcontextprotocol.io)
endpoint so an AI assistant can read and analyse the account's own workouts.
The first purpose is one activity's full context; the endpoint is built so
more read tools can follow.

## 1. Scope and non-goals

In scope: read tools over the account's own workouts — finding a workout, its
complete analysis context, and its measurement series — for an assistant the
account connects with an API token.

Not in scope, deliberately:

- **Writes.** No tool edits, imports, publishes or deletes. The REST API
  (`API.md`) is the programmatic way to change things.
- **Other accounts' data.** No feed, received note, publication or comment
  tool yet. When a `social:read` tool comes, it reads through the publication
  snapshot exactly as the REST API does (§2), whatever the token's location
  level.
- **OAuth.** Web connectors (claude.ai, ChatGPT) require OAuth 2.1 with
  dynamic client registration; that waits for the OAuth contract reserved by
  `API.md`. Desktop and command-line clients send a Bearer header.
- **Prompts, resources, sampling, elicitation, notifications.** The server
  advertises tools only.
- **Health data** beyond what a workout file already carries.

## 2. Privacy invariants

The MCP endpoint is a third door onto the same rooms as the web and the REST
API, never a new room.

1. **Owner data is the owner's.** Every tool reads only the token's account,
   each query scoped through it. A foreign or unknown workout id is a tool
   error saying the workout does not exist on this account — never a hint
   that it exists elsewhere.
2. **Other accounts' data goes through the reader's door.** No tool reads
   another account. A later one reads publications from their sanitized
   snapshot only (`API.md`), and the token's location level never widens what
   a snapshot carries.
3. **No coordinate by default.** Figures, laps, named places, splits, efforts
   and series over distance and time carry no position. Coordinates leave
   only through `include_geometry`, at the token's location level (§4).
4. **The token holder decides where data goes.** Allure cannot know whether
   an assistant runs a local model or forwards to a commercial provider; the
   location level is the account's explicit, per-token answer to that, shown
   at creation and mailed (§4.3).
5. **Nothing here enters a publication or federation.** The endpoint reads;
   it creates no row other than the token's `last_used_at`.

## 3. Endpoint and transport

- `POST /mcp`, Streamable HTTP in **stateless JSON mode**: every POST is one
  complete JSON-RPC exchange answered `application/json`; no `Mcp-Session-Id`
  is issued, no SSE stream is held, so any Puma worker serves any request.
  `GET`, `DELETE`, `PUT` and `PATCH` answer **405** with `Allow: POST` (after
  authentication).
- `McpController < Api::Rest::V1::BaseController`: the REST boundary as is —
  `Authorization: Bearer` only, never the session cookie; 401 for a missing,
  malformed, unknown, revoked or expired token; 403 `account_suspended`,
  `second_factor_required`, `insufficient_scope`; RFC 9457 problems in
  English; the 300-requests-per-minute token limit. Tool calls read, so the
  60-mutations-per-minute bucket does not apply (`mutation_request?` is
  false).
- Every tool needs the **`read`** scope. No new scope: an MCP client is one
  more program acting with the account's read permission.
- The official Ruby SDK (`mcp` gem) builds a fresh `MCP::Server` per request
  (`AllureMcp::Server.build`) with an `AllureMcp::Context` (user, token,
  outcome) as its server context, and
  `MCP::Server::Transports::StreamableHTTPTransport` with `stateless: true`,
  `enable_json_response: true`, `serve_subscriptions_listen: false` and DNS
  rebinding protection off — Rails host authorization checks `Host`, and a
  Bearer token rather than a cookie authenticates, so a rebound page gains
  nothing.
- Server info: name `allure`, title `Allure`, version `Allure::VERSION`,
  website the instance base URL; capabilities `{ tools: {} }`; English
  `instructions` explaining the tools, SI units, UTC timestamps, null meaning
  "not recorded" and contested metrics.

## 4. Location levels

### 4.1 The levels

`api_tokens.mcp_geometry` (string, NOT NULL, default `none`, check
constraint):

| level | what `include_geometry` returns |
|---|---|
| `none` | nothing: `{ available: false, reason: "token_location_level_none" }` |
| `filtered` | the track with **every** point inside an active privacy zone removed, start and finish included — no endpoint exemption, unlike a publishing profile's `mask_start`/`mask_finish`; a track wholly hidden answers `hidden_by_privacy_zones` |
| `raw` | the recorded track, privacy zones included |

Either way the coordinates are `[longitude, latitude]` (GeoJSON order),
recording segments stay separate (`MultiLineString`), each segment is thinned
evenly to its share of `geometry_points` (default 300, at most 2 000) keeping
its first and last point, and values are rounded to five decimals (about a
metre). `Allure::Federation::Privacy::ZoneFilter` does the filtering.

### 4.2 The instance ceiling

`MCP_GEOMETRY_MAX` (`none`, `filtered` or `raw`; unset or unknown means no
ceiling) caps every token: `ApiToken#effective_mcp_geometry` is the lower of
the token's level and the ceiling, read at each request, so lowering the
ceiling also lowers tokens issued before. The creation form offers only the
levels up to the ceiling, and the model refuses a new token above it
(`above_instance_limit`).

### 4.3 Choosing and telling

- The level is chosen once, on `/settings/api/tokens/new`, as a radio list
  (`none` selected) with a hint and the §19.27 warning of `DESIGN.md`. It
  cannot be changed; the account issues another token.
- The token list shows a « Tracés sans zones » / « Tracés complets » badge for
  a token above `none`; the page after creation lists the level.
- The creation mail (`SecurityMailer`, `api_token_created`) adds one sentence
  for `filtered` and `raw`.
- Every `get_workout_context` answer carries `location_level`, so the model
  knows whether a missing track means "not allowed" or "not recorded".

## 5. Tools

Every tool is read-only (`readOnlyHint: true`, `destructiveHint: false`,
`idempotentHint: true`, `openWorldHint: false`), declares
`additionalProperties: false`, and answers one compact JSON text block. Float
noise is rounded to five decimals. A missing or foreign workout and an invalid
argument are tool errors (`isError: true`) with an English sentence the model
can act on; argument-schema violations are refused by the SDK the same way.
Values are SI as persisted (`WORKOUT.md`): metres, seconds, metres per second,
bpm, W; `units` lists them. Paces are seconds per `pace_basis_metres` (1 000,
or 500 for rowing). `account` gives the unit system, time zone and week start.

### 5.1 `get_workout_context`

Arguments: `workout_id` (required), `include_laps`, `include_splits`,
`split_distance` (100–100 000 m), `include_efforts`, `include_training`
(each default true), `include_series` (default false), `series_points`
(default 200), `include_geometry` (default false), `geometry_points`.

Answer:

| key | contents |
|---|---|
| `workout` | the REST owner `Workout` (`API.md`, detail form) without its REST links, plus `web_url`, `local_start`, `sport_details` (slug, English name, family, virtual, pace basis), `average_pace`, `elevation_filter` |
| `equipment` | the REST `Equipment` of each attached item, with its totals |
| `records_set` | the classic records this workout holds (`type`, `metric`, SI value; a pace record is seconds per kilometre) and its best-effort records |
| `laps` | `recorded` laps, `detected` sections grouped by source (climb, descent, stop, pause, loop, route, speed and power intervals; at most 50 per source, `truncated_sources`), null fields dropped |
| `splits` | rows over `split_distance`, defaulting to the pace basis, multiplied by five until at most 60 rows; `grade_adjusted_pace` in s/km where the sport has it |
| `best_efforts` | standard-distance efforts with the owner's personal place |
| `segment_efforts` | the REST `SegmentEffort` plus `own_history`: attempts, best and median own time, this effort's rank among the athlete's own efforts, the previous attempt |
| `training` | the 28 days before: totals for the sport and for every sport, and the last five workouts of the sport as list rows |
| `series` | optional, as §5.3 |
| `geometry` | optional, as §4 |
| `location_level` | the token's effective level |

Owner-only derivations (places, anomalies, detected laps, personal places,
notes) are included: the reader is the owner.

### 5.2 `list_workouts`

Arguments: `sport` (comma-separated slugs), `from`/`to` (dates in the
account's zone), `place`, `query`, `commute`, `limit` (1–100, default 20),
`cursor`. Newest first through `Workouts::ListQuery`; compact rows (id,
title, sport, commute, UTC and local start, distance, times, ascent, average
speed and pace, heart rate, power, places); `next_cursor` is an encrypted
`Api::Rest::V1::Cursor` bound to `mcp:list_workouts`. An unknown sport, a bad
date or a foreign cursor is a tool error.

### 5.3 `get_workout_series`

Arguments: `workout_id` (required), `series` (subset of elevation, speed,
heart_rate, cadence, power; default every recorded one), `from_distance`/
`to_distance` (m) or `from_time`/`to_time` (s from the start), `max_points`
(2–2 000, default 300). `AllureMcp::WorkoutSeries` extracts every point
through `Allure::Gpx::ChartSeries`, filters the range, then thins it with
the same class, which keeps extremes and gap boundaries. The answer is a table
— `columns` (`distance`, `elapsed_time`, the series, and `recording_segment`
when there are several) and `rows` — with `recorded_series`,
`missing_series`, `points_in_range` and `points_returned`. Never a
coordinate.

## 6. Code layout

| path | role |
|---|---|
| `app/controllers/mcp_controller.rb` | boundary and transport |
| `app/mcp/allure_mcp/server.rb` | the per-request server, tool list, instructions |
| `app/mcp/allure_mcp/context.rb` | user, token, outcome |
| `app/mcp/allure_mcp/tools/base.rb` | owner lookup, errors, rounding, shared rows |
| `app/mcp/allure_mcp/tools/*.rb` | one class per tool |
| `app/mcp/allure_mcp/workout_series.rb`, `workout_geometry.rb` | the two track readers |
| `app/mcp/allure_mcp/metrics.rb` | the counter |

The namespace is `AllureMcp`, never `Mcp`, which would sit beside the SDK's
`MCP`. Tools reuse the REST serializers and the services the web uses; no
second implementation of a metric. Constants a subclass needs from
`Tools::Base` inside `class << self` are written `Base::…` (singleton-class
constant lookup does not reach the superclass).

## 7. Settings

`/settings/api` gains an « Assistants IA (MCP) » card after the tokens: one
sentence, the endpoint address (`FEDERATION_BASE_URL` + `/mcp`), and
copyable configurations for Claude Code (command), opencode
(`opencode.json`) and the common `mcpServers` shape (Cursor, LM Studio…) with
a placeholder token. The page after creating a token with `read` shows the
same configurations filled with the fresh secret, once. Client formats are not
translated; their labels are.

## 8. Metrics

`allure_mcp_requests_total{method, tool, outcome}` (`METRICS.md`), from
the SDK's instrumentation callback: `method` is `initialize`, `ping`,
`tools/list`, `tools/call` or `other`; `tool` a known tool name, `unknown`, or
`none`; `outcome` `ok`, `not_found`, `invalid` or `error`. HTTP-level
refusals stay in `rails_requests_total`.

## 9. Verification

`spec/requests/mcp_spec.rb` covers the boundary (401, session ignored, scope,
suspension, 405), the protocol (stateless initialize, tools-only
capabilities, the tool list and its annotations, unknown arguments), each
tool, the owner-only lookup, the absence of coordinates by default and in
series, each location level with a privacy zone, and the ceiling lowering a
token issued before it. `spec/models/api_token_spec.rb` covers the level and
the ceiling; `spec/requests/settings_api_spec.rb` the form, the mail and the
configurations.

## 10. Deferred

- `compare_workouts`, `get_training_summary` (periods, pulse, sport mix) and
  `get_records`.
- `social:read` tools through publication snapshots.
- OAuth 2.1 for web connectors, with `API.md`.
