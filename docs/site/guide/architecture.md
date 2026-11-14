# How an instance works

An Allure instance is one Rails application started in several roles, plus
PostgreSQL and a mail relay, all defined in `docker-compose.production.yml`.

## Containers

| Service | Role |
|---|---|
| `rails` | The web application (Puma) on container port `3000`. On every start it prepares the databases, applies pending migrations and loads the reference catalogs (sports, equipment types). |
| `worker` | Background jobs: imports and analysis, federation delivery, remote media, remote imports, webhooks, photos, push notifications, and the recurring jobs. |
| `route-image-worker` | Renders route images with MapLibre in a headless Chromium, one at a time. It is a separate image (`route-image-worker` build target) so the main image carries no browser. |
| `db` | PostgreSQL 18 with PostGIS 3.6. |
| `smtp-forwarder` | A Postfix relay that only the application can reach. |

No port is published on the host. Your reverse proxy reaches the `rails`
container on port `3000`; see [Reverse proxy and TLS](../install/reverse-proxy).

## Networks

| Network | Members | Internet access |
|---|---|---|
| `backend` | every application container and `db` | no (internal) |
| `mail` | application containers and `smtp-forwarder` | no (internal) |
| `egress` | `rails`, `worker`, `route-image-worker`, `smtp-forwarder` | yes |

The database is never on a network with internet access. Most third-party
traffic — federation delivery, geocoding along routes, weather, map tiles for
images, remote imports, push — runs as background jobs. A few features call out
**during a web request**, which is why `rails` is on `egress` too:

- sign-in through Google, Apple or an OpenID Connect provider;
- the place search when a member draws a privacy zone (with geocoding enabled);
- federation's inbox, which fetches a sender's public key to check a signature.

## Data

Two volumes hold everything worth backing up:

| Volume | Contents |
|---|---|
| `pgdata` | PostgreSQL: the application database plus the queue, cache and cable databases. |
| `allure_storage` | Uploaded originals, route images, photos, avatars, exports, and media received from other instances. |

A third volume, `smtp_spool`, holds mail waiting to be delivered.

There is no Redis: background jobs (Solid Queue) and Action Cable (Solid Cable)
use their own PostgreSQL databases.

## Queues

The `worker` service runs the queues `default`, `solid_queue_recurring`,
`federation`, `federation_media`, `remote_imports`, `webhooks` and `photos`.
The `route-image-worker` runs `route_images` only. Large imports (a Strava
archive, a big batch) run their follow-up work at a lower priority, so new
activities are processed first.

## Third parties an instance may contact

Allure is useful with no third party at all except map tiles. Each of the
following is listed with the variable that controls it.

| Service | When | Controlled by |
|---|---|---|
| OpenFreeMap vector tiles | Members' browsers load the interactive map; the route-image worker renders images | `MAP_STYLE_URL`, `MAP_STYLE_URL_DARK` |
| OpenStreetMap raster tiles | Fallback route images and publication images | `MAP_RASTER_TEMPLATE` |
| A Nominatim-compatible geocoder | Place names along routes and privacy-zone search | `GEOCODING_BASE_URL` (off when unset) |
| An OpenTopoData-compatible server | Terrain elevation for activities without altitude | `ELEVATION_BASE_URL` (off when unset) |
| Open-Meteo | Historical weather, for members who opt in | `WEATHER_ENABLED` (off when unset) |
| Garmin Connect, EXR | Remote imports, for members who link an account | `GARMIN_CONNECT_IMPORT_ENABLED`, `EXR_IMPORT_ENABLED` (off when unset) |
| The push relay | Notifications to the iOS companion | `VAPID_*`, `PUSH_RELAY_ORIGINS` (off until the keys are set) |
| Google, Apple, an OpenID Connect provider | Sign-in, when configured | `AUTH_GOOGLE_*`, `AUTH_APPLE_*`, `AUTH_OIDC_*` |
| Other Allure instances | Federation | `FEDERATION_ENABLED` |
| Members' webhook endpoints | Signed webhook deliveries | Members' own settings |

Every variable is described in the [environment reference](../configuration/environment).
