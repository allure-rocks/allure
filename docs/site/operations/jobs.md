# Background jobs

Imports, analysis, images, federation and every third-party call run as
background jobs in [Solid Queue](https://github.com/rails/solid_queue), stored
in the `allure_production_queue` database. Nothing else (no Redis) is needed.

## Workers and queues

| Container | Queues | Threads |
|---|---|---|
| `worker` | `default`, `solid_queue_recurring`, `federation`, `federation_media`, `remote_imports`, `webhooks`, `photos` | `JOB_THREADS`, 3 by default |
| `route-image-worker` | `route_images` | 1 (Chromium is heavy) |
| `ai-worker` | `ai` | 1 (the model is the bottleneck) |

Some work is limited further on its own, whatever the threads: one geocoding
job at a time by default, one weather job, one assistant call (its own
single-threaded worker), five deliveries per remote instance,
two photo jobs, one job per linked import account, one file import and one
Strava archive per member.

Large imports — a Strava archive, a batch of more than five files, a
date-range retrieval — run their follow-up work at a lower priority, so new
activities are analysed first.

To give the `worker` more room, raise `JOB_THREADS` in `.env.production`, or
`JOB_CONCURRENCY` (processes per container) through an
[override](../install/overrides). Each thread holds a database connection.

## Recurring jobs

| Every | Job |
|---|---|
| 5 minutes | Federation recovery (stuck deliveries, inbox items, remote media, key retirement); webhook recovery |
| 10 minutes | Automatic publishing sweep |
| 15 minutes | Recovery of geocoding, weather, assistant summaries, segment places and photo processing |
| hour (:05) | Remote import synchronisation |
| hour (:12) | Clearing finished jobs from the queue database |
| hour (:20) | Account deletion sweep |
| day (04:30) | Pruning expired sessions |
| day (04:40) | Pruning expired API tokens |
| day (04:45) | Deleting the uploaded files of finished imports, and failing an import stalled for 7 days |
| day (04:50) | Removing expired data exports |

## The jobs console

`/admin/jobs` refreshes every few seconds and shows, per queue, the jobs ready,
scheduled, running, blocked and failed, and the latency; the worker processes
and their heartbeat; the recurring tasks and when they last ran; the next
scheduled jobs; and the 20 newest failures with their error.

- **Failed jobs:** retry or discard one, or all of them.
- **Queues:** pause one (its jobs wait) and resume it.

## Sweeps

When a release improves an analysis, or after you enable a service, existing
data is brought up to date by sweeps. The same page shows how many activities
each sweep would touch and queues it; every sweep can be stopped and resumed
and does nothing when nothing is outdated. Each is recorded in the audit log.

| Sweep | Brings up to date |
|---|---|
| Workout rebuild | Facts and analysis read from the original files. |
| Route images, Segment images | Missing or outdated pictures. |
| Weather | Weather of consenting members' activities. |
| Summaries | Assistant summaries of consenting members' recent activities. |
| Estimated elevation | Terrain elevation of opted-in members' activities without altitude. |
| Workout places | Place lists, from stored geocoding (no request). |
| Workout geocoding | Missing or outdated geocoding. |
| Detected loops | Merges duplicate loop segments. |
| Segment elevation profiles | Missing course profiles (no request). |
| Segment elevation from the service | Terrain elevation of eligible courses. |
| Segment places | Course place names still missing. |
| Outings done together | Detection of shared outings. |
| Heart rate | Heart-rate zones and load. |

The [CLI reference](../reference/cli) lists the matching `bin/rails` tasks,
which accept `AFTER_ID=` to resume a sweep from a given point.
