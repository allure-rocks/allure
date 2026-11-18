---
pageClass: reference-page
aside: false
---

# Environment reference

Every setting is an environment variable. Most are read when used, so a
restart of the containers is enough to apply a change; the exceptions are noted.

The **Compose** column says how the stock `docker-compose.production.yml`
handles the variable:

- **env file** — set it in `.env.production`; the stock file passes it on.
- **override** — the stock file does not pass it; set it through a
  [Compose override](../install/overrides).
- **fixed** — the stock file sets a fixed value; change it only through an
  override.
- **compose** — read by Compose itself, not by the application.

A boolean is on for `true`, `1`, `yes` or `on`. Values marked *required* stop
Compose or the application from starting while they are missing.

## Core

| Variable | Default | Compose | Description |
|---|---|---|---|
| `APP_HOST` | *required* | env file | Public hostname, without scheme or path. Mail links use it, and Rails only answers requests for this host. |
| `ALLOWED_HOSTS` | `APP_HOST` | override | Comma-separated hostnames Rails answers for, replacing `APP_HOST` in that check. |
| `CONTENT_SECURITY_POLICY_SOURCES` | none | env file | Extra space- or comma-separated `https://` origins the browser may reach (fetch, images, sign-in form redirects), added to the Content-Security-Policy. The map styles' hosts, `ROUTE_IMAGE_MAP_ORIGINS` and the enabled identity providers are already allowed. |
| `SECRET_KEY_BASE` | *required* | env file | Signs cookies and derives application secrets. See [Secrets and keys](../install/secrets). |
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` | *required* | env file | Encrypts sensitive columns. Never change it once data exists. |
| `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` | *required* | env file | Encrypts columns that must stay searchable. |
| `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | *required* | env file | Salt for the two keys above. |
| `RAILS_LOG_LEVEL` | `info` | env file | `debug`, `info`, `warn` or `error`. `debug` may log personal data. |
| `INSTANCE_OPERATOR_USERNAME` | none | env file | The single account allowed into `/admin`. Unset: nobody is the operator. |

## Instance funding

See [Instance funding](../features/funding) for the hosted checkout and manual
confirmation workflow. The feature is optional and grants no application access.

| Variable | Default | Compose | Description |
|---|---|---|---|
| `FUNDING_ENABLED` | off | env file | Master switch for the funding page, administration controls, badge preferences and badges. Turning it off retains existing contributions and preferences. |
| `FUNDING_LINK_COFFEE` | none | env file | HTTPS hosted checkout URL for the coffee tier. Missing or invalid URLs have no payment button. |
| `FUNDING_LINK_BEER` | none | env file | HTTPS hosted checkout URL for the beer tier. |
| `FUNDING_LINK_ENERGY` | none | env file | HTTPS hosted checkout URL for the energy-drink tier. Missing or invalid URLs have no payment button. |
| `FUNDING_STRIPE_SECRET_KEY` | none | env file | Stripe API key (`sk_test_…` / `sk_live_…`) used by the server for read-back, portal sessions, recovery and cancellation. Required with the webhook secret to enable the Stripe provider. |
| `FUNDING_STRIPE_WEBHOOK_SECRET` | none | env file | Secret printed by `stripe listen` or shown by the dashboard endpoint, used to verify `POST /funding/webhooks/stripe`. |
| `FUNDING_STRIPE_PRICE_COFFEE` | none | env file | Stripe price id of the coffee annual subscription. |
| `FUNDING_STRIPE_PRICE_BEER` | none | env file | Stripe price id of the beer annual subscription. |
| `FUNDING_STRIPE_PRICE_ENERGY` | none | env file | Stripe price id of the energy-drink annual subscription. |
| `FUNDING_STRIPE_LINK_COFFEE` | none | env file | Stripe payment-link URL for the coffee annual subscription. |
| `FUNDING_STRIPE_LINK_BEER` | none | env file | Stripe payment-link URL for the beer annual subscription. |
| `FUNDING_STRIPE_LINK_ENERGY` | none | env file | Stripe payment-link URL for the energy-drink annual subscription. |

## Database

| Variable | Default | Compose | Description |
|---|---|---|---|
| `ALLURE_DATABASE_PASSWORD` | *required* | env file | Password of the `allure` PostgreSQL role, used to create the database container and by the application. |
| `POSTGRES_HOST` | `db` | fixed | Database host. |
| `POSTGRES_USER` | `allure` | fixed | Database role. |
| `POSTGRES_PASSWORD` | `allure` | fixed | Set by the stock file to `ALLURE_DATABASE_PASSWORD`. |
| `RAILS_MAX_THREADS` | `3` | override | Puma threads per process, and the size of each database connection pool. |

## Web server and workers

| Variable | Default | Compose | Description |
|---|---|---|---|
| `WEB_CONCURRENCY` | unset (one process) | override | Puma worker processes, read by Puma itself. With more than one, request metrics are per process. |
| `SOLID_QUEUE_IN_PUMA` | unset | override | Runs the job supervisor inside Puma. Only for a single-container setup; the stock stack has dedicated workers. |
| `SOLID_QUEUE_QUEUES` | all but `route_images` | fixed | Queues a worker container serves. The stock file gives `route_images` to its own worker. |
| `SOLID_QUEUE_THREADS` | `3` | fixed | Threads per worker process. The stock file sets it from `JOB_THREADS` for `worker` and to `1` for `route-image-worker`. |
| `JOB_THREADS` | `3` | compose | Threads of the `worker` container. |
| `JOB_CONCURRENCY` | `1` | override | Worker processes per worker container. |
| `ALLURE_IMAGE` | `allurerocks/allure:latest` | compose | Image of the application containers. |
| `ALLURE_ROUTE_IMAGE_IMAGE` | `allurerocks/allure-route-image:latest` | compose | Image of the route-image worker. |
| `ALLURE_VERSION` | the release | override | Overrides the version advertised in NodeInfo. Leave unset. |

## Registration and accounts

| Variable | Default | Compose | Description |
|---|---|---|---|
| `ALLOW_REGISTRATION` | `false` in production | env file | `true` opens self-registration to anyone. Invitations work either way. See [Registration](./registration). |
| `AUTH_SESSION_IDLE_DAYS` | `30` | env file | A session closes after this many days without activity. |
| `AUTH_SESSION_MAX_DAYS` | `90` | env file | A session closes this many days after sign-in, whatever the activity. |
| `AUTH_2FA_GRACE_DAYS` | `14` | env file | Days a password account may wait before adding a second factor. `0` asks at the next sign-in. The operator never has a grace period. |
| `IOS_APP_IDS` | none | env file | Comma-separated `TEAMID.bundle.id` identifiers of iOS apps allowed to use this instance's passkeys, served in `/.well-known/apple-app-site-association`. |

## Identity providers

Each provider is enabled when all its required variables are set. They are
read at boot: restart after a change. Callback URLs derive from
`FEDERATION_BASE_URL`. See [Identity providers](../features/identity-providers).

| Variable | Default | Compose | Description |
|---|---|---|---|
| `AUTH_GOOGLE_CLIENT_ID` | none | env file | Google OAuth client ID. |
| `AUTH_GOOGLE_CLIENT_SECRET` | none | env file | Google OAuth client secret. |
| `AUTH_APPLE_SERVICES_ID` | none | env file | Sign in with Apple services ID. |
| `AUTH_APPLE_TEAM_ID` | none | env file | Apple developer team ID. |
| `AUTH_APPLE_KEY_ID` | none | env file | ID of the Sign in with Apple key. |
| `AUTH_APPLE_PRIVATE_KEY` | none | env file | The key's PEM, on one line with `\n` for each newline. |
| `AUTH_OIDC_ISSUER` | none | env file | Issuer URL of a generic OpenID Connect provider. |
| `AUTH_OIDC_CLIENT_ID` | none | env file | Its client ID. |
| `AUTH_OIDC_CLIENT_SECRET` | none | env file | Its client secret. |
| `AUTH_OIDC_LABEL` | `OpenID Connect` | env file | Button label shown to members. |
| `AUTH_OIDC_REQUIRED_ACR` | none | env file | An `acr` value requested from the provider; a sign-in whose token reports another one is refused. |
| `AUTH_OIDC_REQUIRED_AMR` | none | env file | An authentication method (RFC 8176, e.g. `mfa`) the provider's token must list in `amr`; a sign-in without it is refused. For providers whose `acr` never varies, such as Authentik. |

## Instance identity and presentation

See [Instance identity](./instance).

| Variable | Default | Compose | Description |
|---|---|---|---|
| `FEDERATION_BASE_URL` | *required* | env file | The public origin, `https://allure.example.org`. Permanent once federation has run. |
| `FEDERATION_PROTOCOL` | the URL's scheme | fixed (`https`) | Must match the scheme of `FEDERATION_BASE_URL`. |
| `INSTANCE_NAME` | `Allure` | env file | Display name of the instance. Nobody may register it as a username. |
| `INSTANCE_DESCRIPTION` | none | env file | Short description, shown in NodeInfo and the web app manifest. |
| `INSTANCE_HOST_NAME` | none | env file | Who hosts the instance, shown in the footer. |
| `INSTANCE_HOST_URL` | none | env file | A public `http(s)` page for the host, linked from the footer. |
| `ALLURE_SOURCE_URL` | the upstream repository | env file | Where members read the source of the code you run, from the About dialog. Set it when you run a modified version: the AGPL requires offering its source to your members. |

## Federation

See [Federation](../features/federation).

| Variable | Default | Compose | Description |
|---|---|---|---|
| `FEDERATION_ENABLED` | `false` in production | env file | Turns ActivityPub federation on. |
| `FEDERATION_RESTRICTED_ENABLED` | `false` | env file | Lets followers-only publications reach followers on approved peers. Followers on this instance read them either way. |
| `ALLOW_PRIVATE_IPS` | `false` | fixed (`false`) | Lets federation reach private addresses. Only for local test rings; never in production. |

## Mail

See [Mail](./mail).

| Variable | Default | Compose | Description |
|---|---|---|---|
| `MAILER_DOMAIN` | *required* | env file | Domain announced to the mail relay; the relay only accepts senders from it. |
| `MAILER_FROM` | *required* | env file | `From` header, for example `Allure <noreply@example.org>`. |
| `SMTP_HOSTNAME` | *required* | compose | Hostname the Postfix relay announces. Should match the server's reverse DNS. |
| `SMTP_MYNETWORKS` | private ranges | compose | Networks allowed to send through the relay. Keep it limited to the Compose mail network. |
| `SMTP_ADDRESS` | `smtp-forwarder` | fixed | SMTP server the application sends to. |
| `SMTP_PORT` | `587` | fixed | Its port. |
| `SMTP_ENABLE_STARTTLS` | `false` | override | Use STARTTLS when the SMTP server offers it. |

## Maps and route images

See [Maps and route images](./maps).

| Variable | Default | Compose | Description |
|---|---|---|---|
| `MAP_STYLE_URL` | OpenFreeMap `liberty` | env file | MapLibre style document for the light map and route images. |
| `MAP_STYLE_URL_DARK` | OpenFreeMap `dark`, or `MAP_STYLE_URL` when only that is set | env file | Style document for the dark map. |
| `MAP_RASTER_TEMPLATE` | OpenStreetMap tiles | env file | `{z}/{x}/{y}` raster tile URL for fallback and publication images. |
| `ROUTE_IMAGE_MAP_ORIGINS` | none | env file | Extra comma-separated origins the image renderer may fetch from, for styles that load tiles, fonts or sprites from other hosts. |
| `ROUTE_IMAGE_RENDER_TIMEOUT_MS` | `30000` | env file | Time allowed for one rendering, 1 000 to 120 000 ms. |
| `CHROMIUM_EXECUTABLE_PATH` | `/usr/bin/chromium` | fixed | Chromium used by the route-image worker. |
| `NODE_BINARY` | `node` | override | Node executable that runs the renderer. |

## Geocoding

Off while `GEOCODING_BASE_URL` is unset. See [Geocoding](../features/geocoding).

| Variable | Default | Compose | Description |
|---|---|---|---|
| `GEOCODING_BASE_URL` | none | env file | Base URL of a Nominatim-compatible HTTPS service. |
| `GEOCODING_REQUESTS_PER_SECOND` | `10` | env file | Instance-wide request budget. |
| `GEOCODING_CONCURRENCY` | `1` | env file | Geocoding jobs running at once; each paces itself to its share of the budget. Read at boot. |

## Terrain elevation

Off while `ELEVATION_BASE_URL` is unset. See [Terrain elevation](../features/elevation).

| Variable | Default | Compose | Description |
|---|---|---|---|
| `ELEVATION_BASE_URL` | none | env file | Base URL of an OpenTopoData-compatible server, for example `http://opentopodata:5000`. |
| `ELEVATION_DATASET` | `mapzen` | env file | Dataset name on that server. |
| `ELEVATION_INTERPOLATION` | `bilinear` | env file | Interpolation method the server applies. |
| `ELEVATION_SAMPLE_METRES` | `50` | env file | Distance between sampled points along a route. |
| `ELEVATION_REQUESTS_PER_SECOND` | `5` | env file | Request rate towards the server. |
| `ELEVATION_MAX_REQUESTS_PER_WORKOUT` | `40` | env file | Upper bound of requests for one activity. |

## Weather

Off unless `WEATHER_ENABLED` is true. See [Weather](../features/weather).

| Variable | Default | Compose | Description |
|---|---|---|---|
| `WEATHER_ENABLED` | `false` | env file | Offers historical weather to members. |
| `WEATHER_FORECAST_URL` | `https://historical-forecast-api.open-meteo.com` | env file | Historical forecast endpoint, for recent activities. |
| `WEATHER_ARCHIVE_URL` | `https://archive-api.open-meteo.com` | env file | Reanalysis archive endpoint, for older activities. |
| `WEATHER_FORECAST_SINCE` | `2022-01-01` | env file | Activities from this date use the forecast endpoint, older ones the archive. |
| `WEATHER_API_KEY` | none | env file | Open-Meteo commercial API key, if you have one. |
| `WEATHER_REQUESTS_PER_SECOND` | `2` | env file | Request rate towards Open-Meteo. |
| `WEATHER_MAX_REQUESTS_PER_DAY` | `5000` | env file | Requests allowed over any 24 hours; enrichment waits while the budget is spent. |

## Photos

See [Photos](../features/photos).

| Variable | Default | Compose | Description |
|---|---|---|---|
| `PHOTOS_ENABLED` | `true` | env file | `false` hides photo uploads everywhere. |
| `PHOTOS_QUOTA_MB` | `2048` | env file | Default photo storage per account, in megabytes. The operator may change it per account from `/admin`. |

## Remote imports

Each source appears to members only while its flag is on. See
[Remote imports](../features/remote-imports).

| Variable | Default | Compose | Description |
|---|---|---|---|
| `GARMIN_CONNECT_IMPORT_ENABLED` | `false` | env file | Lets members link a Garmin Connect account and import from it. The integration is unofficial and may stop working. |
| `EXR_IMPORT_ENABLED` | `false` | env file | Lets members link an EXR (virtual rowing) account and import from it. The integration is unofficial and may stop working. |
| `WITHINGS_IMPORT_ENABLED` | `false` | env file | Lets members link a Withings (connected watches) account and import from it. The integration is unofficial and may stop working; only a day-long session is kept, never the password. |
| `ZWIFT_IMPORT_ENABLED` | `false` | env file | Lets members link a Zwift (virtual cycling and running) account and import from it. The integration is unofficial and may stop working; only an eight-day refresh token is kept, never the password. |

## Push notifications

Off until all three VAPID values are set and valid. See
[Push notifications](../features/push).

| Variable | Default | Compose | Description |
|---|---|---|---|
| `VAPID_PUBLIC_KEY` | none | env file | Public half of the VAPID key pair (`bin/rails push:vapid_keys`). |
| `VAPID_PRIVATE_KEY` | none | env file | Private half. |
| `VAPID_SUBJECT` | none | env file | A contact for the relay: `mailto:` address or `https://` URL. |
| `PUSH_RELAY_ORIGINS` | `https://push.allure.rocks` | env file | Comma-separated relay origins the instance may push to. |

## API and AI assistants

See [API, webhooks and MCP](../features/api).

| Variable | Default | Compose | Description |
|---|---|---|---|
| `MCP_GEOMETRY_MAX` | no ceiling | env file | Most location an API token may hand to an AI assistant through `/mcp`: `none`, `filtered` (privacy zones removed) or `raw`. |

## Workout assistant

Off until both `AI_BASE_URL` and `AI_MODEL` are set. See
[Workout assistant](../features/assistant).

| Variable | Default | Compose | Description |
|---|---|---|---|
| `AI_BASE_URL` | none | env file | Root URL of an OpenAI-compatible endpoint, for example `http://litellm:4000`. No `/v1` of its own. |
| `AI_MODEL` | none | env file | Model name or proxy alias; the assistant is offered only when this and `AI_BASE_URL` are both set. |
| `AI_API_KEY` | none | env file | Bearer key for the endpoint, when it requires one. |
| `AI_REQUEST_OPTIONS` | none | env file | JSON object merged into every request body, for example `{"reasoning_effort":"none"}` to turn a model's thinking mode off. |
| `AI_TIMEOUT` | `300` | env file | Seconds allowed for one model answer. |
| `AI_MAX_REQUESTS_PER_DAY` | `500` | env file | Provider calls allowed over any 24 hours; work waits while the budget is spent. |

## Monitoring

| Variable | Default | Compose | Description |
|---|---|---|---|
| `METRICS_TOKEN` | none | env file | Bearer token for the Prometheus endpoint `/metrics`. Unset: the endpoint answers 404. |

## Demo instance

An all-or-nothing mode for a throwaway public instance whose database is
recreated from the development seed every night and whose accounts'
credentials are published on the sign-in page. Never enable it on an instance
that holds real data: the accounts named by `DEMO_ACCOUNTS` cannot change
their credentials, no session IP is ever stored, and no second factor is owed
by anyone (the operator included). Deployment: `docker-compose.demo.yml` and
the demo runbook (maintained with the source).

Keep `demo.env` operator-readable only (`chmod 600`); it is excluded from Git
and the Docker build context. The demo always runs an operator (the Compose
file defaults it to `marie`): `DEMO_OPERATOR_PASSWORD` is required, assigned
by the seed on every pass so it survives the nightly reset, and never shown
on the sign-in page. The application refuses to boot if the operator is among
the shared accounts, if it is configured without `DEMO_OPERATOR_PASSWORD`, if
that password is shorter than 15 characters, or if it is the shared password;
the seed also refuses the public development constant. The seed's local
relationships do not require external federation, which stays disabled in the
demo deployment.

The Linux host runs `bin/demo-nightly-reset` from cron every minute. It pins
the `allure-demo` Compose project explicitly, validates configuration before
deleting volumes, and waits for the server's `/up` healthcheck after seeding.
It never pulls images: the demo changes version only when you pull the
production and route images, rebuild the demo image on the host, and reset.
The demo image is never published (it carries third-party corpus data).
An exclusive `flock` and the date in `tmp/demo-reset/last-success` prevent
overlapping or repeated successful resets. Missed schedules and failed runs
are retried after the scheduled time; keep this host-side state across deploys.

| Variable | Default | Compose | Description |
|---|---|---|---|
| `DEMO_INSTANCE` | off | override | The master switch for the demo mode. |
| `DEMO_ACCOUNTS` | none | override | Comma-separated usernames whose credentials are published and protected. Must exclude `INSTANCE_OPERATOR_USERNAME`; otherwise boot fails. |
| `DEMO_PASSWORD` | none | override | The shared password displayed on the sign-in page. Unset hides the line. |
| `DEMO_OPERATOR_PASSWORD` | none | override | The operator's stable password on a demo instance, assigned by the seed and never published. Required with `INSTANCE_OPERATOR_USERNAME`; at least 15 characters and different from `DEMO_PASSWORD`. |
| `DEMO_RESET_AT` | `03:00` | override | The nightly reset, `HH:MM` in `TZ`; the host-side wrapper reads the same value, so the schedule exists in exactly one place. |
| `DEMO_DATASET` | `full` | fixed (`full`) | Which seed manifest `bin/rails demo:reset` seeds. |

## Feedback to GitLab

An optional widget that lets members file an annotated screenshot as a GitLab
issue. The stock file turns it off.

| Variable | Default | Compose | Description |
|---|---|---|---|
| `GITLAB_ENABLED` | `false` | fixed (`false`) | Shows the feedback widget. |
| `GITLAB_API_URL` | `https://gitlab.com/api/v4` | override | GitLab API base URL. |
| `GITLAB_PROJECT_ID` | none | override | Numeric project ID or `namespace/project` path. |
| `GITLAB_TOKEN` | none | override | Project token allowed to create issues; never sent to browsers. |
| `GITLAB_LABELS` | `feedback,allure` | override | Labels given to each issue. |
| `GITLAB_CONFIDENTIAL` | `false` | override | Creates confidential issues. |
