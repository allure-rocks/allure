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
  in the summary; no title is ever renamed automatically.
- **Additive**: a summary never changes a metric, a record, an effort, a
  publication or a notification.
- **Automatic within 30 days** of the workout's start (`AUTO_WINDOW`), on
  request beyond it, so an archive import cannot monopolize the GPU.
- **One checkable number per sentence**: every number in the text must come
  from the facts the sentence cites (§4.4). A summary whose only surviving
  sentence fails the rule is `failed`, never shown.
- **One sentence is a complete answer**: a quiet outing says one true sentence
  and stops; the answer is bounded to three sentences and the model is never
  asked to pad (§4.1).
- **Ruby computes, the model chooses**: the facts are true and verified, and
  nothing decides the summary's angle in Ruby. No fact is imposed as the
  opening, the facts are grouped by theme rather than ranked, and no style
  example is shown — a small model copies what it is shown, and the previous
  prompt produced the same figure-then-record opening almost every time
  (§3.4, §4.1).
- **The voice is the interface's** (DESIGN.md §3.1–§3.2): a training partner
  texting right after the outing, direct and a bit cheeky, with at most one
  exclamation mark for a personal best. The sport's own vocabulary is an offer
  of one word at most, never a list, and most summaries take none
  (§4.1). The sober register stays reserved for privacy, publishing and
  destructive actions (DESIGN.md §3.2).
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

`POST {AI_BASE_URL}/v1/chat/completions`, `Authorization: Bearer {AI_API_KEY}`
when a key is set, `Content-Type: application/json`. `AI_BASE_URL` is the
proxy's root (no `/v1` of its own), which is what the reference deployment and
`.env.example` use.

Body: `model` (`AI_MODEL`), `messages`, `temperature` (the summary asks for
0.7 — warmer than a data extraction, since the verifier, not the temperature,
guards every number, and a little warmth keeps the wording from settling into
one formula — lowered to 0 on the verification retry), `max_tokens`
(`Allure::Assistant::Client::MAX_TOKENS`, 1 200 — **always set**, the reference
endpoint stalled without it), `stream: false`, and:

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
- **A thinking mode is an operator experiment, not a default.** When
  `AI_REQUEST_OPTIONS.reasoning_effort` names anything but `none`,
  `Client#reasoning?` is true and the call drops `response_format`: the
  reference LiteLLM/Qwen pairing answered a schema-constrained request with an
  empty `content` (the whole answer stayed in `reasoning_content`, at every
  effort level) and a usable answer in prompt-only mode. The prompt then
  carries the answer shape itself (§4.1). The measured cost on the reference
  deployment was about two minutes and 2 200 completion tokens per summary,
  against nine seconds and a few dozen without thinking; the local comparison
  is the place to judge the result (§11).
- `reasoning_content` (and any `reasoning` object a provider adds) is ignored
  and never stored. The local comparison may capture it with
  `capture_reasoning: true` to show why a fact was chosen; the job never does.
  A `content` that still carries a ` thinking…</think>` block is stripped before
  validation.
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

`Workouts::ContextPayload` (`app/services`) builds the owner-only body
(`account`, `units`, `workout`, `equipment`, `records_set`, `laps`, `splits`,
`best_efforts`, `segment_efforts`, `training`) from the same services and REST
serializers. `AllureMcp::Tools::GetWorkoutContext` keeps its token handling,
adds `location_level` and the optional series and geometry, and delegates the
rest; the summary reads the same object, geometry off — one implementation of
every metric. The `workout` section already carries the weather summary, the
heart-rate zones and the toponymy's places the REST serializer serves, so the
facts read them there.

The summary builder adds `include_history: true`, a section the MCP tool does
not ask for (MCP.md §5.1): one year of the same sport before this workout, as
one bounded `pluck` per section and never a point. It carries
`window_days` (365), `same_sport` rows (local start, SI distance, moving time,
ascent, average speed, average heart rate, place names), `older_same_sport`
(whether the sport has older outings beyond the year), `last_same_sport_at`
(the most recent earlier workout of the sport, every origin included, so a
typed session also ends a gap), `previous_workouts`
(the account's count before this workout, every sport), `year_to_date` totals
for the sport in the member's own calendar year, and `places` — for each of
this workout's places, whether it was visited before and how many workouts this
year passed there. Manual entries stay out of `same_sport`: comparing a
recorded ride with a typed one is not a comparison of outings; they still
count in the year totals and in `last_same_sport_at`. The same section carries
`sport_workouts` (every earlier outing of the sport, every origin included) so
the model can weigh a record against a lifelong habit, and `route_places` — the
whole recorded route in order with each place's nature (`hut`, `pass`,
`summit`, …), which the capped display list loses.

`include_companions: true` adds `companions`: the people on the outing, from a
mutual confirmation only — a pending invitation, a refusal or a withdrawal
names nobody. Each entry carries the displayed name, and how many earlier
outings the owner and that person already shared in either direction
(`previous_together`, `previous_this_year`). A local participant resolves to
the account's display name, a remote one to the actor's name or handle. The
section exists only for the summary: the MCP payload never asks for it
(§8).

It adds `:course`, the route cut into sections (`Allure::Insights::Course`,
`Allure::Insights::CoursePlan` and `Allure::Gpx::RouteProfile`). The cut follows
the climbs and descents the laps already detected — the same ones the workout
page shows — and fills the ground between them; when no climb was detected, or
when the stored elevation cannot be trusted, equal parts give the shape of the
outing instead (three, four beyond 8 km). The cut keeps at most eight sections,
never keeps two claims on the same ground, absorbs a gap shorter than 5 % of the
route (at most 1,5 km) into its neighbour, and never leaves a hole: the
boundaries cover the whole recorded distance. A route under 3 km has no course.

`RouteProfile#call(boundaries:)` measures each section in one pass over
`PointStream`: its distance, its moving time, its ascent and descent, the
distance whose elevation is known, its average heart rate over the moving time,
and — for the sports whose flat-equivalent pace means something — the
grade-adjusted distance and time. The boundaries are the detected laps' own
scale, so a climb lands in the section it names; a pause or a recording gap
between two segments is never bridged, and a stationary interval never enters
the moving time. The point stream's elevations are already the canonical
filtered profile (WORKOUT.md), so nothing is smoothed twice. No point, no
coordinate and no raw series leaves Ruby. The MCP does not ask for the course.

`Workouts::SummaryFacts` returns the snapshot the prompt is built from: the
facts, the digest, the locale, the units and the course.

### 3.2 A fact

A flat hash, never a sentence the model must complete:

| key | contents |
|---|---|
| `id` | stable string (`record:best_effort:km10`, `segment:rank:<id>`, `training:ratio`, `weather:wind`), the model cites it and the verifier resolves it |
| `kind` | `baseline`, `record`, `segment`, `comparison`, `training`, `history`, `place`, `company`, `course`, `pacing`, `heart_rate`, `weather`, `climb`, `interval`, `section` |
| `display` | the value in the member's units and language (« 62,4 km », « 1,6 fois votre activité moyenne sur 28 jours (50,0 km) ») |
| `value` | the SI number when the fact has one, else `nil` |
| `unit` | the SI unit symbol; a short token for a dimensionless value (`%`, `rank`, `share`, `count`, `ratio`); else `nil` |
| `direction` | `up`, `down` or `flat`, relative to the member's better direction, else `nil` |
| `sentiment` | `good`, `bad` or `neutral` |
| `weight` | 0–100, a tie-breaker for the prompt's bound only (§3.4); it never orders the prompt or marks a fact as the story |
| `source` | the context section the detector read (`workout`, `records_set`, `best_efforts`, `segment_efforts`, `training`, `history`, `companions`, `course`, `splits`, `laps`) |

### 3.3 Detectors

Each returns zero or more facts and never fabricates one: a missing source is
simply no fact.

- `baseline` — always present: the local date, the sport, the distance, the
  moving time, the ascent when there is one, and the sport's preferred average
  (a pace for a pace-led sport, a speed otherwise).
- `record` — a classic record this workout holds, and a best effort that holds
  one of the athlete's three best times over its standard distance. A record
  of the other measurement family is dropped: a pace on a sport that reads in
  speed, a speed on a sport that reads in pace. In metric, the imperial
  standard distances (`mi5`, `half_mile`, …) stay out; an imperial member keeps
  both vocabularies. While the sport has fewer than five outings, the label
  carries the size of the history behind it (« Plus grande distance : 11,1 km
  (votre première sortie) », « (sur 4 sorties) »): the record is true and says
  little, and the model can see as much without a threshold of ours.
- `segment` — a leaderboard podium (at least three participants: being first
  of one is no achievement) or an effort among the athlete's three best on that
  segment, with the time; and the effort against the athlete's own median on
  that segment once they have ridden it five times, from five seconds.
- `comparison` — the same segment against the athlete's previous attempt
  (`own_history`): the delta in time, from five seconds.
- `training` — the four weeks before the sport: their volume, and the workout
  against the sport's average workout of the window when the ratio is under
  0.7 or at least 1.3.
- `history` — the year before, all from `history` and never a fabricated
  figure:
  - the pace against the usual one over a comparable distance (0.6 to 1.6
    times this one, at least four outings in the last ninety days), from three
    percent; the sport's preferred average decides whether it reads in pace or
    speed, and a slower day stays neutral;
  - the same pace for a different heart rate (within three percent of the pace,
    at least three outings), from four bpm;
  - the longest workout and the biggest climb since a date, when nothing
    matched or beat them in the last sixty days (or in the year at all), and no
    record already says it;
  - the fastest pace (or speed, as the sport reads) since a date, same window,
    among the outings of at least 0.6 times this distance, from three of them,
    when no average record already says it;
  - no "since" fact at all under five outings of the sport in the year, nor
    when the previous outing of the sport is more than sixty days back: the gap
    is the story then, and it is told alone;
  - the closest comparable outing of the last ninety days (distance within
    ten percent, ascent within a quarter or fifty metres), preferring the one
    that shares the most places, compared on the pace (or the speed), from two
    percent — never on the moving time, whose delta is mostly the distance;
  - the gap since the last workout of the sport, from fourteen days, naming the
    sport; a typed session counts as the previous workout;
  - the round year total this workout crossed, in the member's own units (every
    100 to 1 000, then every 500);
  - the sport's lifetime count before this outing (`history:sport_count`), so
    the model can weigh a record against a lifelong habit instead of the code
    deciding what a record is worth; the very first outing says so
    (« Randonnée : première sortie »).
- `place` — the whole recorded route in order (« Par Chevreuse, Dampierre »),
  with a hut, a pass, a summit or another natural feature named as such
  (`place:route`); a first visit once the account has ten workouts behind it,
  and a place visited at least five times this year. A first visit names its
  position on the route (« Première visite : Le Tour (départ) »), so a
  departure, a passage and an arrival do not read alike. The nature comes from
  `workout_place_names.kind`, never guessed from the name. The id carries the
  place's position (`place:first:0`), never its name, so the model copies an
  id it cannot misspell. A virtual workout reduces all of it to one
  `place:venue` fact (« Monde : Watopia »).
- `company` — who was there, from a mutually confirmed participation only:
  the names (`company:with`), a first outing with someone (`company:first:<n>`)
  and the Nth outing together this year for the person with the longest shared
  history (`company:regular:<n>`). Never a pending invitation, a refusal, a
  withdrawal or a co-presence suggestion.
- `section` — one line of the course, context by nature and never a reason to
  write more (§3.4): where
  it runs (« de 4,2 km à 9,8 km »), what it is (a detected climb with its name,
  length, grade and ascent; a descent with its drop; flat or rolling, read from
  the measured ascent; « section » for the equal cut), its pace or speed, its
  gap to the workout's own average from two percent (never on a descent), its
  average heart rate, and the climb's flat-equivalent pace when the sport
  computes one. Every number the model may write is already in the line.
- `course` — what the sections say, always on comparable ground:
  - a faster finish and a fade: the last level section against the first,
    from 3 % faster and 5 % slower. A fade is never claimed when the heart
    rate came down: that is a harder finish, not a collapse;
  - the climb held: the biggest climb's flat-equivalent pace within 3 % of
    the mean of the level sections', when at least 90 % of the climb's moving
    time qualifies;
  - the same pace for more heart: the first and last level sections within
    3 % of pace and a heart rate at least 5 % higher — the drift a raw series
    cannot tell apart from the terrain;
  - more than 40 % of the moving time spent climbing, over at least two
    climbs.
- `pacing` — the fastest split, from the non-partial splits.
- `heart_rate` — the average and the maximum, and the dominant zone when the
  profile's zones were sliced.
- `weather` — the headwind and tailwind shares of the route when the headwind
  is a real obstacle (at least a quarter of the distance), and one conditions
  fact carrying what the provider measured: the condition, the temperature
  range, the apparent temperature, the wind and its gusts, precipitation and
  night; only from a `ready` row. The code suppresses only what carries no
  information (a dry day's zero millimetres, a light wind's share); a plain
  16 % headwind made the model open on « le vent de face n'a touché que 16 % du
  parcours ». Whether the weather is worth telling is the model's call.
- `climb` — the biggest detected climb: its name, length and grade.
- `interval` — the detected fast intervals: their count and the longest.

### 3.4 Selection

Every fact normally travels: the model chooses what the outing is about. The
selection keeps at most 40 facts, far above what the detectors produce, and only
a pathological workout loses its lowest `weight` extras; the bound is a prompt
limit, not a ranking. The order is stable, so the digest is stable. Nothing marks a fact as the story: there is no
highlight, no notable threshold and no per-kind cap. No sentence count is
derived from the facts either — the answer is bounded to three sentences (§4.1).
A `section` is context by nature: it is appended after the facts, never competes
for the slots and never lengthens the answer.

The prompt groups the facts by theme in a fixed order (record, segment,
comparison, training, history, place, company, course, pacing, heart rate,
weather, climb, interval), never by weight. The only editorial hint is the
screen: the figures the workout page already renders (`baseline`) travel apart
from the facts it does not show (§4.2).

### 3.5 Formatting

`Allure::Insights::Format` turns SI values into the member's units through
`Allure::Units` and the `units.*` locale keys, with the rules and number
delimiters of `WorkoutsHelper#format_distance` and its neighbours
(§3.5 of [DESIGN.md](DESIGN.md)), at the precision each fact asks for. A spec
renders a fixed sample through both paths, in metric and imperial and in the
five locales, and requires identical strings: the formatter may not drift from
the UI. The fact labels themselves live under `insights.facts.*` in the five
locale files.

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
  language (workout → activité, personal best → record, and so on), with the
  note that the sport's own vocabulary may replace one of those words in a
  sentence;
- the voice of [DESIGN.md](DESIGN.md) §3.1–§3.2, one step past the ordinary
  playful register: « a training partner texting right after the outing: warm,
  direct, a bit cheeky. Spoken language, never a report. » The athlete is the
  subject, and a sentence may open on a place, the weather, a person or a
  detail before it reaches the athlete — the opening is not fixed. The verbs
  are the sport's own, and the model is given the administrative words to avoid
  in that language (inscrit, fixe, établi, offert, « a pris son temps »). The
  address form is spelled out — `vous` in French, `du`/`tú`/`je` in German,
  Spanish and Dutch (DESIGN.md §3.4–§3.4b). Sentences run to 20 words, the
  rhythm is spoken and the lengths uneven, a fragment is allowed; the model is
  told to link what belongs together, to avoid opening two sentences the same
  way, and to keep at most one warm or wry remark that is true of this outing.
  At most one « but » in the summary; the date and the sport name are never
  restated, the page already shows them; one exclamation mark at most, reserved
  to a personal best or a first; no emoji, no slogan, no fake congratulation; a
  hard day stays kind. The two defects to avoid by name are the administrative
  verb and the summary written around figures instead of around the athlete.
  The prompt writes no model sentence: the earlier « you rode 204.6 km »
  illustration is exactly what produced « Vous avez avalé 54,9 km » on every
  ride;
- the free narrative instruction: « Choose what this outing is about. One
  detail usually carries it: a climb, a place, the weather, the people, the
  shape of the route, a number. Tell that one, and let the rest go. The facts
  marked as already on the page are rarely worth repeating; the ones the page
  does not show are often the story. Most outings need one or two sentences,
  three only for a big day. Never list the facts, and stop as soon as the story
  is told. » Nothing imposes an opening: the previous prompt's « Start with the
  number or the action » plus its highlighted record is what made almost every
  summary begin with a figure and a personal best. The instruction gives the
  length as an expectation, not as a range to fill: « write between 1 and 4 »
  read as four slots, one fact per sentence;
- the sport's vocabulary as an offer, not a glossary: two ordinary words of
  the family, plus one climb word when the outing climbed, with « borrow it »
  and « most summaries need none ». A sport without a family gets no line. No
  word carries a number or a unit, so jargon can never replace a unit the
  verifier does not check (§3.5);
- « The course table describes the route in order. Use it to tell the shape of
  the outing: where it climbed, where the pace was easy or hard, how it ended.
  Never walk through the sections one by one; pick the one or two that carry
  the story. A slow section that climbs is the road, not a verdict on the
  effort. Never claim fatigue, loss or a constant effort unless a course fact
  says it. Cite the section ids you use. »;
- « Use only the facts below. Never invent a number, a place, a person, a time
  or a comparison. You may name a place or a person that a fact carries, to set
  the scene, but never one it does not carry. Every sentence cites at least one
  fact id, in its `fact_ids` field and never in the text. Write at most the
  stated number of sentences, and stop as soon as the story is told. Write
  every number in digits with its unit, exactly as its fact writes them. A word
  may replace another, never a unit. Rephrase the fact labels freely: they are
  data, not prose. »;
- the title is a punchy nickname, 2 to 6 words and at most 60 characters; it
  uses only numbers the facts carry, a place, a person or a detail from the
  facts makes a good one, and it is never the sport and the date alone the way
  an import names a file;
- the answer shape itself, as one compact JSON object (`title`, `sentences`,
  each sentence's `text` and `fact_ids`), so the prompt-only path and a
  thinking mode need no schema (§4.3).

There are no style examples. A small local model copies what it is shown: the
three examples of the previous prompt produced the same figure, colon,
personal-best opening in most summaries. The voice paragraph describes the
register; it never models a sentence. The sport's vocabulary stays, but as two
or three words offered once, never a list to place.

The answer is bounded to `1..3` sentences (`Prompt::SENTENCES`), not derived
from the facts. One true sentence is complete, and the prompt tells the model
to stop as soon as the story is told; a quiet outing is never padded and a rich
one is never walked through fact by fact. The prompt also says that most
outings need one or two sentences, so the bound reads as a ceiling rather than
a target.

### 4.2 User prompt

The sport, the local date and the length expectation (« usually one or two,
three at most »), then every fact under one
of two headings: « Facts already shown on the workout page (rarely worth
repeating) » for the `baseline` figures, and « Facts the page does not show »
for everything else, in the fixed thematic order of §3.4. A line is
`id | display`; there is no sentiment column, no weight and no highlight line.
The grouping is about the screen, not the story: it tells the model what the
member can already read, and leaves the choice of angle to it.

Then, apart from the facts, the course: `section:1` to `section:8` in route
order, each with its terrain, its pace and its heart rate. Keeping the course
out of the facts table is what stops it from competing for the summary's angle.
Never a coordinate. The only places and people the model may name are the ones
a `place` or `company` fact carries.

The verifier checks the numbers, not the proper nouns: a model that names a
place or a person the facts do not carry is not caught mechanically. The prompt
forbids it, and the only names the model sees are the `place` and `company`
facts — but a hallucinated toponym stays possible, and acceptable only because
the summary is the owner's own screen (AI.md §1). A partner's name is sent to
the model only after a mutual confirmation, and the consent copy says so (§7).

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
      "minItems": 1,
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
shape. `maxItems` is the fixed bound of §4.1, clamped to five; `minItems` is
one, because a quiet outing is a complete answer.

### 4.4 Verification

`Allure::Insights::Verifier` applies these checks:

1. every `fact_id` resolves to a fact of the snapshot;
2. every number in a sentence occurs in the union of the `display` strings of
   the facts **that sentence cites** — compared on digits only, after removing
   space, narrow-space and `'` thousands separators and ignoring `°` and unit
   suffixes. A decimal separator belongs to its number: `11,4` is `114`, not
   `11` and `4`, so a title can no longer borrow `11` from `11,4 %`, the way
   « Le Cheylas à 11 km/h » passed the check of a `11,4 %` section;
3. a sentence that writes one of the snapshot's fact ids in its text is
   dropped: the id is data for the machine, and a small model does slip
   (« La montée de section:4 … »);
4. a title that writes a fact id, or fails the number rule, is dropped, the
   sentences stay;
5. a sentence that fails is dropped and logged with its fact ids
   (`Rails.logger.warn`, never the text);
6. no surviving sentence triggers one retry at `temperature: 0` with the
   refused sentences and their facts; still none, the row is `failed`;
7. sentences beyond the prompt's bound are dropped, never rewritten: the
   prompt-only fallback does not enforce `maxItems` by itself.

The verifier never rewrites a sentence; it drops it. It checks numbers and
fact ids, not proper nouns: a place or a person the model invents is not caught
here. The facts are the only names it sees, and a place or company fact never
enters a publication or a programmatic surface (§8).

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
| `last_error` | a closed code on `failed`: `rejected` (a terminal 4xx), `invalid` (no usable JSON, or no verified sentence) or `unavailable` (429, 5xx or timeout after the retries) — never a provider message |

A `facts` snapshot may carry the displayed name of a confirmed participant in
a `company` fact. It is owner-only, travels with the account export (§8), and
never enters a publication or a programmatic surface.

`users.ai_enabled` boolean, default `false`, not null.

`workouts.title_source` string, not null, default `owner`:

| Value | Meaning |
|---|---|
| `default` | the importer's generated title (« Course à pied le 3 mars ») |
| `file` | the track's own name |
| `owner` | typed by the member, or accepted from a suggestion |

The importer stamps `owner` when its form carried a title, `file` when the
track named itself and `default` otherwise; the edit form and « Utiliser ce
titre » stamp `owner`. The block offers the suggested title only while the
source is `default` or `file`. The migration stamps every existing row `owner`,
so no historical title is ever proposed for replacement. A database check
constraint carries the three values, like `workouts_origin`.

No marker is added to `workouts`: a summary's staleness is its row's `version`
and `facts_digest` ([DERIVATIONS.md](DERIVATIONS.md) §3).

## 6. Pipeline

- **Eligibility** (`Workouts::SummaryEligibility`): the assistant configured,
  the owner opted in and not deactivated, `recording?`, and a stored analysis
  (`analysis_version` above zero). A refusal never writes a row: nothing is
  queued, nothing is generated, and the block is not rendered.
- `Workouts::SummaryRefresh.schedule(workout)` is the single scheduling seam,
  like `ToponymyRefresh`:
  - it returns untouched when eligibility fails;
  - it builds the facts and the digest (cheap, no network);
  - it returns untouched when a `ready` row already carries the current
    digest and version, and when the workout started before `AUTO_WINDOW` and
    the call is neither an explicit request nor a participation change
    (`bypass_window`);
  - otherwise it marks the row `pending` and enqueues
    `Workouts::GenerateSummaryJob` on the `ai` queue with
    `wait: 30.seconds`, so a burst of derivations produces one run.
  It is called:
  - at the end of `Segments::MatchWorkoutJob` (the analysis, its laps and its
    efforts are settled);
  - at the end of `Workouts::EnrichToponymyJob`: the places are facts, and the
    digest only moves when they changed;
  - at the end of `Workouts::EnrichWeatherJob` and `HeartRates::RezoneJob`;
  - by `Participations::SummaryRefresh` when a participation becomes
    confirmed (`Participations::Decide`,
    `Federation::Inbox::ParticipationAnswer#accept`) — the source workout and,
    for a link, the participant's own recording. A confirmation bypasses
    `AUTO_WINDOW`: a name must not outlive it on an old workout either. When the
    row was already `pending`, `schedule` leaves it alone (the running job
    computed its facts before), so the service enqueues one recheck five
    minutes later; that job recomputes the digest and regenerates only if it
    moved. A withdrawal first destroys a summary whose facts carry a `company`
    fact, so a name never outlives the confirmation while the regeneration
    waits, then schedules the same workouts;
  - by the block's request (`POST /workouts/:id/summary`), which bypasses
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
     once at temperature 0 when the verification leaves no sentence;
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
- An import of an older workout changes the history the newer summaries were
  written from, but does not regenerate them: the GPU budget is bounded, and a
  generation happens on the next trigger or on the owner's request. This is
  deliberate, not an omission.

## 7. UI and copy

- **Consent** `/settings/assistant` (group Système, rendered only while the
  instance configures a model): what the assistant does, the switch « Rédiger
  les synthèses de mes activités », the second switch « Afficher aussi la
  synthèse quand une description existe » once the first is on, the §19.40
  sentence — which says that the measurements of the workout and the names of
  its confirmed participants are sent to the model, without using « partagée »,
  reserved for publishing elsewhere in the privacy copy — then « Supprimer les
  synthèses
  enregistrées » when at least one exists (confirmation-guarded, like the
  weather deletion) and « Rédiger les
  synthèses de mes activités récentes » right after opting in.
- **Workout page**: an owner-only block inside the figures card, under its
  primary tiles (DESIGN.md §10.26, §20.3), filling the card's width. The
  owner's description leads the block; the summary takes that place when the
  workout has no description, and joins the description only when the account
  turned on « Afficher aussi la synthèse quand une description existe ». It is
  absent for a reader, a participant, a manual entry and a credit row, and a
  description-only page shows no assistant block at all. Anatomy:
  - the sentences run as one flowing paragraph (one to three sentences, never
    more); a small info icon closes the last line and carries the §19.40
    attribution in its tooltip and accessible name;
  - the proposed title appears below the text only while `title_source` is
    `default` or `file`, with « Utiliser ce titre »: the action sets the title
    and stamps `owner`, then reloads the page, so the line disappears for good;
  - « Régénérer la synthèse » lives in the page header's `⋯` menu, never in
    the block, and only while the row is `ready`; it is disabled within five
    minutes of the last request, the tooltip naming the wait. A `failed` row
    says « Réessayer » on its sentence's line;
  - states: `pending` — three muted skeleton lines under a `role="status"`
    sentence « Rédaction de la synthèse… »; `ready`; `failed` — one sentence on
    what failed and « Réessayer », never a provider message; outside
    `AUTO_WINDOW` and missing — the empty state with its one action « Rédiger
    la synthèse »;
  - the page renders the block on load; the instance ships the browser's
    Turbo but not the server-side Turbo Streams stack, so the block is not
    replaced live while a generation runs: the owner reloads to see the
    result. A follow-up may add the stream (signed, owner-scoped) with that
    stack.
  - the block announces its ready state once through `aria-live="polite"` —
    the section and the fact that it is ready, never a re-reading of the text
    ([DESIGN.md](DESIGN.md) §18.8).
- **Member limit**: one request per workout per five minutes (`requested_at`
  comparison); the queue serializes the rest. The operator's
  `AI_MAX_REQUESTS_PER_DAY` is the instance ceiling.
- Every string in `fr.yml`, `en.yml`, `de.yml`, `es.yml` and `nl.yml`.

## 8. Programmatic surfaces

None in this version:

- the REST `Workout` detail does not carry the summary;
- `get_workout_context` returns neither the summary nor the `history` and
  `companions` sections the assistant reads it from; a participant's name is
  not a measurement and never leaves the summary path;
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

For a local blind reading, run `dip rails dev_tools:insights_compare ACCOUNT=marie LIMIT=8`
to list the workouts, then repeat with `CALL=1` on an opted-in development account.
Use `IDS=id1,id2` (the printed short ids) to keep the same selection across runs.
The candidate defaults to `PROMPT=legacy`, the previous prompt kept only in
`devtools/lib/dev_tools/legacy_summary_prompt.rb`; `PROMPT=reference` instead
runs the production prompt on both sides, for a model-only comparison.
`OPTIONS='{"reasoning_effort":"medium","max_tokens":5000}'` merges provider
options into the candidate's request, which is how a thinking mode is measured
without changing the instance; `DIRECTION="..."` appends an editorial
instruction to the candidate. `MODEL`, `TEMP` and `TOKENS` override the
candidate's model alias, temperature and output token limit. Both sides
otherwise inherit the instance options and use the same snapshot, schema,
verification and verification retry as the job. Read the two series and mark
preferences in `pairs.txt` before opening `diagnostics.txt`; `diversity.txt`
counts the openings, the records, the repeated three-word phrases, the fact
kinds cited and, when the snapshot carried one, how often a company, weather or
place fact was used. The reasoning, when the candidate asked for it, is printed
there and never stored. These are private local files under `tmp/insights-*`;
remove the run directory after review. No summary is persisted to the database.

- `spec/lib/allure/insights/`: each detector (pure), including every history
  and place threshold and its quiet case, the record family, its scale on a
  young sport and the imperial distances, the company facts and their
  confirmation rule, the weather conditions fact and the light wind it leaves
  out, the course's sections and their summary facts, the prompt's free
  selection, its two fact groups, its optional vocabulary and its spoken
  rhythm, the digest, the formatter's parity with `WorkoutsHelper`, and the
  verifier's outcomes, including a decimal that must match whole.
- `spec/lib/allure/gpx/route_profile_spec.rb`: the boundaries, an interval
  that straddles one, the moving time across a pause, the segment break, the
  missing elevation, the heart rate and the positionless recording.
- `spec/lib/allure/insights/course_plan_spec.rb`: the terrain cut, overlapping
  claims, a short gap, the eight-section cap, the equal parts and the
  determinism.
- `spec/services/workouts/summary_facts_spec.rb`: the context wiring — the
  history and course sections reach the detectors, the terrain cut and the
  equal-part fallback, and the digest is stable.
- `spec/lib/allure/assistant/client_spec.rb` (WebMock): success, `json_schema`
  refusal then prompt-only retry, 429 retry, timeout, `reasoning_content`
  stripped, `AI_REQUEST_OPTIONS` merged without overriding, `max_tokens`
  always present.
- `spec/jobs/workouts/generate_summary_job_spec.rb`: success, digest no-op,
  verification retry, terminal failure, ineligible workout (no row), and the
  prompt-only call a thinking mode asks for.
- `spec/services/participations/summary_refresh_spec.rb`: a confirmation
  schedules the summary and rechecks a row that was already being written, an
  old workout is regenerated past `AUTO_WINDOW`, and a withdrawal drops one
  carrying a company fact before scheduling the next.
- Eligibility, `AUTO_WINDOW`, the five-minute throttle and the daily cap.
- Request specs: the owner's block in each state, the description-first rule,
  the 404 for another account, the title action and `title_source`, the
  five-minute throttle, the consent page, and the block absent from a reader's
  page.
- `spec/services/workouts/context_payload_spec.rb`: the history section's
  exclusions (later workouts, other sports, manual entries in `same_sport`),
  the gap's last outing (`last_same_sport_at`, typed sessions included), the
  year-to-date scope, the place counts and kinds, and the companions — a
  confirmed participation only, both directions of a shared outing, the first
  and repeated counts, never a pending, declined or withdrawn row, and a
  remote name kept on one line.
- `spec/jobs/workouts/enrich_toponymy_job_spec.rb`: the summary is scheduled
  once the places are known, and a summary error never replays the geocoding.
- `spec/docs/environment_reference_spec.rb` and the five locale files.
- `dip fed_test` is unchanged: nothing federates.
