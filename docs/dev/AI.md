# Assistant contract

Allure writes a short summary of a workout from facts it computed itself, and
later answers questions about the member's own data. This document defines the
provider seam, the facts, the prompt and its verification, the data model, the
pipeline, the surfaces and the limits. The conversation is deferred (§10); the
foundation it needs is written here.

## 1. Scope and decisions

- **One provider seam**: an OpenAI-compatible chat-completions endpoint,
  typically a LiteLLM proxy in front of a locally hosted model. No provider
  abstraction and no vendor SDK: plain `Net::HTTP`. The URL is
  operator-configured, exactly like `ELEVATION_BASE_URL` and
  `GEOCODING_BASE_URL`; it is not subject to the federation's SSRF guard, and
  it is never rendered to a member.
- **Two-level opt-in**, like terrain elevation and weather: the instance
  offers the assistant only while `AI_BASE_URL` and `AI_MODEL` are both set,
  and every account carries `users.ai_enabled`, default `false`.
- **Ruby computes, the model phrases** (`lib/allure/insights/`). The model
  receives neither the track nor a point, a coordinate or a raw series: only
  the selected facts, already formatted in the member's units and language.
- **Owner-only, never shared.** A summary never enters a publication snapshot,
  a federation object, a remote note, a webhook or the public timeline. It is
  not part of the REST representation, the MCP answer or the ActivityPub wire
  in this version (§8).
- **The model proposes, the member decides**: the suggested title is an action
  on the card; no title is ever renamed automatically.
- **Additive**: a summary never changes a metric, a record, an effort, a
  publication or a notification.
- **Automatic within 30 days** of the workout's start (`AUTO_WINDOW`), on
  request beyond it, so an archive import cannot monopolize the GPU.
- **One checkable number per sentence**: every number in the text must come
  from the facts the sentence cites (§4.4). A summary that cannot satisfy this
  is `failed`, never shown.
- **The answer's model name is stored** and takes part in the regeneration
  marker.
- Opting out stops every future request immediately. Stored summaries remain
  until the member presses « Supprimer les synthèses enregistrées » (§7).
- A manual entry, a credit row and a workout whose analysis never completed
  get no summary. A positionless recording and a virtual workout do: nothing
  positional is ever sent.

## 2. Provider contract

The reference deployment is LiteLLM in front of a Qwen-family model; the
paragraphs below record what that pairing required, which is the behaviour the
client is written and tested against.

`POST {AI_BASE_URL}/chat/completions`, `Authorization: Bearer {AI_API_KEY}`
when a key is set, `Content-Type: application/json`.

Body: `model` (`AI_MODEL`), `messages`, `temperature` (0.3, lowered to 0 on
the verification retry), `max_tokens` (`Allure::Assistant::Client::MAX_TOKENS`,
1 200 — **always set**, the reference endpoint stalled without it),
`stream: false`, and:

```json
{"type": "json_schema", "json_schema": {"name": "workout_summary", "strict": true, "schema": {"...": "§4.3"}}}
```

- `response_format` is only ever `json_schema` or absent. The reference
  endpoint rejects `json_object` with a 400 ("'response_format.type' must be
  'json_schema' or 'text'"), so a refusal of `json_schema` is retried once
  **without** `response_format`, the schema and its rules restated in the
  prompt (prompt-only mode). `json_object` is never sent.
- `AI_REQUEST_OPTIONS` is a JSON object merged into the body after those keys.
  It may not override `model`, `messages`, `stream` or `response_format`. It
  exists because the way to turn a model's thinking mode off belongs to the
  engine behind the proxy, not to Allure: the reference Qwen ignores
  `chat_template_kwargs`, `enable_thinking` and a `/no_think` system message,
  and obeys `{"reasoning_effort": "none"}`.
- `reasoning_content` (and any `reasoning` object a provider adds) is ignored
  and never stored. A `content` that still carries a ` thinking…</think>` block
  is stripped before validation.
- The answer's `usage` feeds the token metrics; its `model` is what
  `workout_summaries.model` stores.
- Errors: a 400 is terminal, except the one `json_schema` fallback; 401, 403
  and 404 are terminal; 429 and 5xx are retried with exponential back-off
  (three attempts); a transport error or a timeout is retried like a 5xx.
  `AI_TIMEOUT` is 300 s by default: the model may take the time it needs.
- The first version does not stream. The conversation (§10) adds
  `stream: true` with `stream_options: {"include_usage": true}` and parses the
  SSE `data:` lines; the summary needs the complete object to be verified, so
  it stays a single call.
- `Allure::Assistant::Config` reads every value at call time: `AI_BASE_URL`,
  `AI_MODEL`, `AI_API_KEY`, `AI_REQUEST_OPTIONS`, `AI_TIMEOUT` (default 300),
  `AI_MAX_REQUESTS_PER_DAY` (default 500, counted like the weather budget:
  the sum of `requests_count` over the rows touched in the last 24 hours).
  `enabled?` is true only when the URL and the model are both present.

## 3. Facts (pure, `lib/allure/insights/`)

### 3.1 Input

`Workouts::ContextPayload` is extracted from
`AllureMcp::Tools::GetWorkoutContext`: the owner-only body (`account`, `units`,
`workout`, `equipment`, `records_set`, `laps`, `splits`, `best_efforts`,
`segment_efforts`, `training`) built from the same services and the same REST
serializers. The MCP tool keeps its token handling, its `location_level` and
its optional geometry, and delegates the rest. The summary reads the same
object with geometry off — one implementation of every metric.

### 3.2 A fact

A flat hash, never a sentence the model must complete:

| key | contents |
|---|---|
| `id` | stable string (`record:10k`, `segment:123:rank`, `training:distance_28d`, `weather:headwind`), the model cites it and the verifier resolves it |
| `kind` | `baseline`, `record`, `segment`, `comparison`, `training`, `pacing`, `heart_rate`, `weather`, `climb`, `interval` |
| `display` | the value in the member's units and language (« 62,4 km », « 2:41 de plus que votre médiane sur 28 jours ») |
| `value` | the SI number when the fact has one, else `nil` |
| `unit` | the SI unit symbol, else `nil` |
| `direction` | `up`, `down` or `flat`, relative to the member's better direction, else `nil` |
| `sentiment` | `good`, `bad` or `neutral` |
| `weight` | 0–100, the selection rank |
| `source` | the context section it came from |

### 3.3 Detectors

Each returns zero or more facts and never fabricates one: a missing source is
simply no fact.

- `baseline` — always present: the sport, the local date, the distance, the
  moving time, the ascent, and the sport's preferred average.
- `record` — a classic record or a best effort that holds a personal place,
  with its margin.
- `segment` — a segment effort with its rank, the athlete's own best, median
  and previous attempt on that segment.
- `comparison` — the same loop or route against the previous attempt
  (`own_history`, loop reuse): the delta in time.
- `training` — the 28 days before the sport: distance and moving time against
  the 28 days before those, then the week against the week.
- `pacing` — the second half against the first, from the splits, and the
  fastest split.
- `heart_rate` — the drift between the two halves of the recorded series, the
  average against the 28-day average of the sport, and the zone distribution
  when the profile exists.
- `weather` — the headwind and tailwind shares, the mean headwind, the
  temperature range and the dominant condition.
- `climb` — the biggest detected climbs: length, ascent and grade.
- `interval` — the detected effort blocks: count, length, pace or power.

### 3.4 Selection

`Facts.select` returns at most 16 facts: every `baseline` fact, then the
highest `weight`, at most three per kind, ties broken by kind order and then by
`id`. The order is stable, so the digest is stable.

### 3.5 Formatting

`Allure::Insights::Format` turns SI values into the member's units through
`Allure::Units` and the `units.*` locale keys, with the precision and the
number delimiters of `WorkoutsHelper#format_distance` and its neighbours
(§3.5 of [DESIGN.md](DESIGN.md)). A spec renders a fixed sample through both
paths, in metric and imperial and in the five locales, and requires identical
strings: the formatter may not drift from the UI.

### 3.6 Digest

`facts_digest` is the SHA-256 of the canonical JSON of
`{version, locale, unit_system, facts}`. Any change to a fact, the selection,
the locale or the units re-generates the summary.

## 4. Prompt, schema and verification

### 4.1 System prompt

Written in English; the answer is in the member's language. It states:

- the model is the instance's assistant and writes the summary of one workout
  for its owner;
- the target language and the [DESIGN.md](DESIGN.md) §4 glossary of that
  language (workout → activité, personal best → record, and so on);
- « Use only the facts below. Never invent a number, a place, a person, a time
  or a comparison. Every sentence cites at least one fact id. Two to five
  sentences. Sober register, second person, no exclamation, no emoji, no
  training advice that a fact does not support. Write every number in digits,
  exactly as its fact writes it. »;
- the title is at most 60 characters and obeys the same rule as the sentences.

### 4.2 User prompt

A table of `id | display | sentiment`, then the sport and the local date.
Never a coordinate, a place name absent from the facts, or an account name.

### 4.3 Schema

```json
{
  "type": "object",
  "additionalProperties": false,
  "required": ["title", "sentences"],
  "properties": {
    "title": {"type": "string", "maxLength": 60},
    "sentences": {
      "type": "array",
      "minItems": 2,
      "maxItems": 5,
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["text", "fact_ids"],
        "properties": {
          "text": {"type": "string", "maxLength": 400},
          "fact_ids": {"type": "array", "minItems": 1, "items": {"type": "string"}}
        }
      }
    }
  }
}
```

No `oneOf`, no deeper nesting: the reference endpoint returned nothing in 180 s
on a schema with a nested object per sentence, and answered in 12 s on this
shape.

### 4.4 Verification

`Allure::Insights::Verifier` applies these checks:

1. every `fact_id` resolves to a fact of the snapshot;
2. every number in a sentence occurs in the union of the `display` strings of
   the facts **that sentence cites** — compared on digits only, after
   normalising `,` and `.` decimals and space, narrow-space and `'` thousands
   separators, and ignoring `°` and unit suffixes;
3. a title that fails the same rule is dropped, the sentences stay;
4. a sentence that fails is dropped and logged with its fact ids
   (`Rails.logger.warn`, never the text);
5. fewer than two surviving sentences trigger one retry at `temperature: 0`
   with the refused sentences and their facts; still fewer than two, the row is
   `failed`.

The verifier never rewrites a sentence; it drops it.

## 5. Data model

`workout_summaries`, one row per workout (unique `workout_id`, FK cascade):

| Column | Notes |
|---|---|
| `status` | `pending` / `ready` / `failed` |
| `locale` | the member's locale at generation; a locale change makes the digest stale |
| `version` | `Allure::Insights::VERSION` |
| `facts` | the selected facts (jsonb): the replayable snapshot the conversation will seed from, and what a support question can be answered from |
| `facts_digest` | §3.6 |
| `title` | the proposed title, `nil` on failure |
| `sentences` | `[{text, fact_ids}]` (jsonb) |
| `model` | the model name the answer carried |
| `requests_count` | provider calls spent on this row |
| `requested_at` | the last explicit member request, the five-minute throttle key |
| `generated_at` | |
| `last_error` | a closed code on `failed`: `rejected` (a terminal 4xx), `invalid` (no usable JSON, or fewer than two verified sentences) or `unavailable` (429, 5xx or timeout after the retries) — never a provider message |

`users.ai_enabled` boolean, default `false`, not null.

`workouts.title_source` string, not null, default `owner`:

| Value | Meaning |
|---|---|
| `default` | the importer's generated title (« Course à pied le 3 mars ») |
| `file` | the track's own name |
| `owner` | typed by the member, or accepted from a suggestion |

The importer stamps `owner` when its form carried a title, `file` when the
track named itself and `default` otherwise; the edit form and « Utiliser ce
titre » stamp `owner`. The card offers the suggested title only while the
source is `default` or `file`. The migration stamps every existing row `owner`,
so no historical title is ever proposed for replacement. A database check
constraint carries the three values, like `workouts_origin`.

No marker is added to `workouts`: a summary's staleness is its row's `version`
and `facts_digest` ([DERIVATIONS.md](DERIVATIONS.md) §3).

## 6. Pipeline

- **Eligibility** (`Workouts::SummaryEligibility`): the assistant configured,
  the owner opted in and not deactivated, `recording?`, and a stored analysis
  (`analysis_version` above zero). A refusal never writes a row: nothing is
  queued, nothing is generated, and the card is not rendered.
- `Workouts::SummaryRefresh.schedule(workout)` is the single scheduling seam,
  like `ToponymyRefresh`:
  - it returns untouched when eligibility fails;
  - it builds the facts and the digest (cheap, no network);
  - it returns untouched when a `ready` row already carries the current
    digest and version, and when the workout started before `AUTO_WINDOW` and
    the call is not an explicit request;
  - otherwise it marks the row `pending` and enqueues
    `Workouts::GenerateSummaryJob` on the `ai` queue with
    `wait: 30.seconds`, so a burst of derivations produces one run.
  It is called:
  - at the end of `Segments::MatchWorkoutJob` (the analysis, its laps and its
    efforts are settled);
  - at the end of `Workouts::EnrichWeatherJob` and `HeartRates::RezoneJob`;
  - by the card's request (`POST /workouts/:id/summary`), which bypasses
    `AUTO_WINDOW`;
  - by `Settings::AssistantController#update` when the member opts in
    (`Workouts::UserBackfillJob` kind `summaries`, last 30 days);
  - by `Workouts::SummaryRecoveryJob` (every 15 minutes in production): a
    `pending` row untouched for 2 hours and a `failed` one older than 6 hours
    created within 2 days;
  - by `Workouts::BackfillSummariesJob` (id cursor, 100) over the last 30 days
    for a missing row, a `failed` row, or a `version` below the current one.
- `Workouts::GenerateSummaryJob` (queue `ai`):
  1. re-checks eligibility; a `pending` row whose member opted out in the
     meantime is deleted (it produced nothing), and the job stops;
  2. rebuilds the facts and the digest (the schedule may be stale) and writes
     nothing when they already match;
  3. calls `Allure::Assistant::Client#complete` with §4;
  4. falls back to prompt-only mode on a `json_schema` refusal and retries
     once at temperature 0 when the verification leaves fewer than two
     sentences;
  5. writes `ready` and broadcasts the card;
  6. on a terminal error writes `failed` with its code, broadcasts, and
     reports through `Rails.error`; a retryable error is left to the job's
     retries and the recovery sweep.
- The day's budget is checked before the call, like the weather budget; when
  it is reached the job raises and is retried hourly (24 attempts, like the
  weather budget), the row staying `pending`.
- A workout or an account deleted while a job is queued makes it a no-op: the
  row went with the cascade.
- Workout and account deletion cascade. Opting out keeps the `ready` rows
  until the member deletes them (§7).

## 7. UI and copy

- **Consent** `/settings/assistant` (group Système, rendered only while the
  instance configures a model): what the assistant does, the switch « Rédiger
  les synthèses de mes activités », the §19.40 sentence, then « Supprimer les
  synthèses enregistrées » when at least one exists (confirmation-guarded,
  like the weather deletion) and « Rédiger les synthèses de mes activités
  récentes » right after opting in.
- **Workout page**: a `[Synthèse]` card between the social row and the weather
  card, owner-only. It is absent for a reader, a participant, a manual entry
  and a credit row. Anatomy in DESIGN.md §10.26:
  - the sentences run as one flowing paragraph (two to five sentences, never
    more); the attribution sentence sits under it, muted, always rendered and
    never behind a disclosure;
  - the proposed title appears below the text only while `title_source` is
    `default` or `file`, with « Utiliser ce titre »: the action sets the title
    and stamps `owner` through a Turbo Stream that replaces the header and the
    card, so the line disappears for good;
  - card header actions: « Régénérer » (ghost), disabled while `pending` and
    within five minutes of the last request, the tooltip naming the wait; a
    `failed` row says « Réessayer »;
  - states: `pending` — three muted skeleton lines under a `role="status"`
    sentence « Rédaction de la synthèse… »; `ready`; `failed` — one sentence on
    what failed and « Réessayer », never a provider message; outside
    `AUTO_WINDOW` and missing — the empty state with its one action « Rédiger
    la synthèse »;
  - the page subscribes with `turbo_stream_from [current_user, :summaries]`;
    the job broadcasts a `replace` to `[workout.user, :summaries]` for the
    card's dom id. The stream name is signed and rendered only on the owner's
    pages; a spec proves a non-owner page renders no stream tag.
  - the card announces its ready state once through `aria-live="polite"` —
    the section and the fact that it is ready, never a re-reading of the text
    ([DESIGN.md](DESIGN.md) §18.8).
- **Member limit**: one request per workout per five minutes (`requested_at`
  comparison); the queue serializes the rest. The operator's
  `AI_MAX_REQUESTS_PER_DAY` is the instance ceiling.
- Every string in `fr.yml`, `en.yml`, `de.yml`, `es.yml` and `nl.yml`.

## 8. Programmatic surfaces

None in this version:

- the REST `Workout` detail does not carry the summary;
- `get_workout_context` does not return it;
- no webhook event, no federation tag, no publication key, no `weather`-style
  received representation.

The reason is the same in each case: a summary is model output about the
owner, not a measurement, and a programmatic consumer would take it as data.
The conversation (§10) is the programmatic path and runs server-side.

The account export does carry it, because it is the member's own data
([ACCOUNT.md](ACCOUNT.md) §3.3).

## 9. Operations

- `/admin/system`: whether the assistant is configured, the endpoint host
  (never the key), the model alias, the day's requests against the cap, and
  the last 24 hours' outcomes.
- `/admin/jobs`: a « Synthèses » card with the pending count and one audited
  sweep (`summaries_backfill_enqueued`), and `bin/rails workouts:summaries`
  (`AFTER_ID=` to resume).
- `/metrics`: `allure_workout_summaries{status}`,
  `allure_ai_requests_total{kind,result}`,
  `allure_ai_request_duration_seconds{kind}` (histogram) and
  `allure_ai_tokens_total{kind,direction}`; `ai` joins the fixed queue
  vocabulary of `allure_jobs_*`; `Metrics::Catalog` mapping and the i18n guard
  ([METRICS.md](METRICS.md)).
- Queues: `ai`, one thread. A dedicated `ai-worker` service in
  `docker-compose.yml` and `docker-compose.production.yml`, never in the main
  worker, whose three threads would compete for one GPU. `ai` stays out of the
  main worker's `SOLID_QUEUE_QUEUES` and out of `config/queue.yml`'s default
  list.
- Configuration is documented in `docs/site/configuration/environment.md`,
  `.env.example` and `production.env.example` in the same patch that reads it.
- The federation ring and the seeds leave every `AI_*` variable unset: nothing
  in a test run calls a model.

## 10. Deferred: the conversation

The second version adds a member asking questions in their own language:

- the conversation starts from a workout's `facts` snapshot (§5) and then
  opens to the account's history;
- tools: `list_workouts`, `get_workout_context` and `get_workout_series`,
  called in-process, plus `get_totals` (per sport and period, compared with the
  previous period) so the model never adds numbers itself;
- at most four tool rounds, then an answer;
- `stream: true` and SSE, appended to the page through a
  conversation-scoped signed stream;
- `ai_conversations` and `ai_messages`, carried by the export, cascading with
  the account.

Nothing of it ships here, and nothing here forecloses it: the client's
non-streaming call is the single provider seam both versions use.

## 11. Tests

- `spec/lib/allure/insights/`: each detector (pure), the selection's
  determinism, the digest, the formatter's parity with `WorkoutsHelper`, and
  the verifier's outcomes.
- `spec/lib/allure/assistant/client_spec.rb` (WebMock): success, `json_schema`
  refusal then prompt-only retry, 429 retry, timeout, `reasoning_content`
  stripped, `AI_REQUEST_OPTIONS` merged without overriding, `max_tokens`
  always present.
- `spec/jobs/workouts/generate_summary_job_spec.rb`: success, digest no-op,
  verification retry, terminal failure, ineligible workout (no row).
- Eligibility, `AUTO_WINDOW`, the five-minute throttle and the daily cap.
- Request specs: the owner's card in each state, the 404 for another account,
  the title action and `title_source`, the consent page, the Turbo Stream tag
  absent from a non-owner page, and the broadcast on completion.
- `spec/docs/environment_reference_spec.rb` and the five locale files.
- `dip fed_test` is unchanged: nothing federates.
