# Monitoring

## Health check

`GET /up` answers `200` once the application has booted, `500` if it failed
to. It does not check the database or the workers. It answers over plain HTTP
and is not logged, but the request must still carry your hostname in `Host`:

```sh
curl -fsS https://allure.example.org/up
```

## Prometheus metrics

`/metrics` serves Prometheus text for Grafana or any compatible scraper. It is
**off** until you set a token:

```sh
# .env.production
METRICS_TOKEN=…   # openssl rand -hex 32
```

Without the token the endpoint answers 404 and computes nothing; with a wrong
token, 401.

Scrape it through your reverse proxy, with the token as a bearer credential:

```yaml
# prometheus.yml
scrape_configs:
  - job_name: allure
    scheme: https
    metrics_path: /metrics
    authorization:
      credentials: "<METRICS_TOKEN>"
    static_configs:
      - targets: ["allure.example.org"]
```

A scraper on the Compose network must still use HTTPS through the proxy, or at
least send your hostname in `Host`: Rails refuses other hosts and redirects
plain HTTP.

### What is exported

Labels are fixed vocabularies — statuses, queue names, providers. **No metric
carries a domain, account, identifier or content**, and database figures are
cached for 15 seconds, so frequent scrapes cost little.

| Area | Families |
|---|---|
| Build and process | `allure_info{version}`, `allure_process_*`, `allure_gc_*` |
| HTTP | `rails_requests_total`, `rails_request_duration_seconds`, `rails_view_runtime_seconds`, `rails_db_runtime_seconds` |
| Jobs | `allure_jobs_{ready,scheduled,claimed,blocked,failed,paused}{queue}`, `allure_jobs_latency_seconds{queue}`, `allure_jobs_processes{kind,state}`, `allure_jobs_recurring_last_run_age_seconds{task}`, `allure_jobs_database_up` |
| Accounts | `allure_users{state}`, new and active accounts over 7 and 30 days, `allure_sessions_open`, `allure_users_second_factor{state}`, `allure_users_sign_in_methods{method}` |
| Activities | `allure_workouts`, distance and moving time totals, `allure_workout_publications{status,audience}`, `allure_segment_publications`, `allure_segments`, `allure_segment_efforts` |
| Imports | `allure_import_batches{status,source}`, `allure_import_failed_entries`, `allure_import_connection*` |
| Federation | `allure_federation_*` — see [Federation](../features/federation#metrics) |
| API and push | `allure_api_*`, `allure_mcp_requests_total`, `allure_webhook_*`, `allure_push_*` |
| Storage | `allure_storage_blobs`, `allure_storage_bytes`, per record type, `allure_database_size_bytes{database}`, `allure_photos`, `allure_photo_bytes` |
| Other | `allure_account_exports`, `allure_account_deletions_scheduled`, `allure_workout_weathers`, `allure_weather_requests_total` |

### Several web processes

Request counters live in each Puma process. With `WEB_CONCURRENCY` above 1,
each scrape sees only the process that answered; keep a single process (the
default) if you rely on request metrics. Database-derived figures are the same
from every process.

## Grafana dashboard

The repository ships a dashboard, `docs/grafana/allure.json`. In Grafana, open
**Dashboards → New → Import**, upload the file and pick your Prometheus data
source. Its variables select the data source, the scrape job, the instance and
the queue; version changes appear as annotations. Its rows cover instance
health, HTTP, background jobs, federation, usage, imports, API and push,
authentication and resources.

It defines no alerts. Good first candidates:

| Alert on | Expression idea |
|---|---|
| Workers down | `allure_jobs_processes{state="alive"}` dropping to 0 |
| Queue backlog | `allure_jobs_latency_seconds` above a few minutes |
| Failed jobs | `allure_jobs_failed` increasing |
| Federation stuck | `allure_federation_deliveries_open_oldest_age_seconds` above a day |
| Disk | your host's own disk metrics, plus `allure_storage_bytes` growth |

## Logs

Every container logs to standard output, so `allure logs -f rails worker`
follows them. Rails tags each line with its request id. `RAILS_LOG_LEVEL`
(default `info`) sets the verbosity; `debug` can log personal data. Known secret
parameters are filtered from request logs; keep `RAILS_LOG_LEVEL` at `info`
and restrict access to the logs.
