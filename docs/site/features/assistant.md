# Workout assistant

Members who opt in at `/settings/assistant` get a short written summary of each
activity, on the activity's page. Allure computes the figures itself, formats
them in the member's units and language, and the model only puts them into
words; it writes a proposed title beside the summary, and the member decides
whether to use it.

## What leaves the instance

Only for members who opted in, and only for their own activities:

- the measurements of the activity and the facts Allure derived from them:
  distance, times, elevation, averages, records, segment efforts, the training
  of the last 28 days, the year's history, the weather when enabled, the
  heart-rate zones when configured, the places of the route and, for a shared
  activity, the displayed name of each confirmed participant;
- a proposed title and one to three sentences, sent back.

Never a position, a track point, a route, a photo, the original file, private
notes, a pending invitation, or another account's data beyond the displayed
name of a confirmed participant. The summary never enters a publication, a
federation object, the REST API or the MCP endpoint. Members can withdraw
consent and delete the stored summaries from the same page.

## Verification

Every number in a sentence must come from a fact that the sentence cites, and
the citations travel with the answer. A sentence that fails is dropped, a title
that fails is dropped, and a summary left with no verified sentence is retried
once at a lower temperature before being marked failed. A failed summary shows a
retry action, never a provider message.

## Provider

Any OpenAI-compatible chat-completions endpoint works. The reference setup is
[LiteLLM](https://docs.litellm.ai) in front of a locally hosted model:

- the client posts to `{AI_BASE_URL}/v1/chat/completions`;
- it always sets `max_tokens`, and asks for a JSON Schema
  (`response_format: json_schema`); the endpoint that rejected `json_object`
  is retried once without `response_format`, with the answer shape restated in
  the prompt;
- `AI_REQUEST_OPTIONS` carries whatever the engine needs. Qwen models, for
  instance, ignore `chat_template_kwargs` and `enable_thinking` and obey
  `{"reasoning_effort":"none"}`; any thinking text that still reaches the
  answer is stripped before verification. A thinking mode
  (`{"reasoning_effort":"medium","max_tokens":5000}`) is an experiment: Allure
  then asks for the answer in the prompt, because the reference engine returns
  an empty answer when a JSON Schema constrains a thinking model, and the
  reference deployment takes around two minutes per activity.

## Configuration

```sh
AI_BASE_URL=http://litellm:4000
AI_MODEL=qwen
# Optional:
# AI_API_KEY=
# AI_REQUEST_OPTIONS={"reasoning_effort":"none"}
# AI_TIMEOUT=300
# AI_MAX_REQUESTS_PER_DAY=500
```

The assistant is offered only while `AI_BASE_URL` and `AI_MODEL` are both set.

## Queue and budget

- The assistant has its own `ai` queue, served by the `ai-worker` service with
  a single thread. The main worker never takes these jobs.
- `AI_MAX_REQUESTS_PER_DAY` caps provider calls over any 24 hours; when it is
  spent, work waits and resumes hourly.
- `429`, `5xx` and timeouts are retried three times; a recovery job retries
  recent failures every 15 minutes.
- A summary is only written automatically for activities started in the last
  30 days. Older ones are written on request, from the activity's page, so an
  archive import never queues months of model calls.

## Existing activities

Recent activities are summarised automatically. A member can ask for one from
the activity's page; `/admin/jobs` (« Synthèses ») or
`bin/rails workouts:summaries` queues the last 30 days, and a member can do the
same from `/settings/data`. Both only schedule work: the `ai` queue paces the
model.

## Metrics

`allure_workout_summaries{status}`, `allure_ai_requests_total{kind,result}`,
`allure_ai_request_duration_seconds{kind}` and
`allure_ai_tokens_total{kind,direction}`.
