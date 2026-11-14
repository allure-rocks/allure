# Troubleshooting

Start with `allure ps` (is everything running?), `allure logs --tail 200 rails
worker`, and `/admin/system` and `/admin/jobs` in the browser.

## The application does not start

| Symptom in `allure logs rails` | Cause |
|---|---|
| Compose refuses to start: `… is required` | A required variable is empty in `.env.production`. |
| `Missing Active Record Encryption configuration` | One of the three `ACTIVE_RECORD_ENCRYPTION_*` keys is missing. |
| An error about `FEDERATION_BASE_URL` | It must be an absolute `https://` URL with no path, and its scheme must match `FEDERATION_PROTOCOL`. |
| `MAP_STYLE_URL …` or `MAP_RASTER_TEMPLATE …` | The map URL is not absolute, not http(s), contains credentials, or the template lacks `{z}`, `{x}` or `{y}`. |
| Database connection refused | `db` is not healthy yet, or `ALLURE_DATABASE_PASSWORD` changed after the volume was created (see [Secrets](../install/secrets#database-password)). |

## Every page answers 403, or redirects in a loop

- **403 everywhere:** the `Host` header the proxy sends is not `APP_HOST`.
- **Redirect loop:** the proxy talks to Rails over HTTP and also redirects
  HTTP to HTTPS on its side for the same request; Rails assumes it is behind
  TLS and must receive every request through the TLS proxy.

## Activities stay "processing"

Imports and their follow-up work run on the `worker`; images on the
`route-image-worker`.

1. In `/admin/jobs`, check that both kinds of process are alive and that the
   queues are not paused.
2. Look at the failed jobs: the error tells which step failed.
3. A large import (a Strava archive) is processed behind new activities on
   purpose; the latency of `default` shows how far behind it is.

## Route images are missing or plain

The route-image worker renders through Chromium and the map style. If tiles
cannot be fetched it falls back to a raster basemap, then to a route without a
map. Check that the worker reaches your `MAP_STYLE_URL` and the tile hosts it
names (list extra hosts in `ROUTE_IMAGE_MAP_ORIGINS`), and raise
`ROUTE_IMAGE_RENDER_TIMEOUT_MS` on a slow machine. Then queue *Route images* in
`/admin/jobs`.

## Uploaded files or images disappear after a restart

The storage volume is not mounted where the application writes. It must be
`allure_storage:/rails/storage` on `rails`, `worker` and `route-image-worker`;
releases up to 0.8.7 mounted it elsewhere. See
[Upgrading](./upgrading#after-0-8-7-the-storage-volume-moves-to-rails-storage).

## Mail does not arrive

`allure logs smtp-forwarder` shows each delivery. `status=sent` means the
receiving server accepted it — look in the spam folder. `status=deferred` or
`bounced` with a reason about reverse DNS, SPF or blocked port 25 means the
host cannot deliver directly: see [Mail](../configuration/mail).

## Federation

| Symptom | Check |
|---|---|
| Remote instances cannot find your accounts | `curl` WebFinger and the actor from outside (see [Federation](../features/federation#checking-it)), and `FEDERATION_ENABLED=true`. |
| Your follows stay pending | Every follow is approved by hand on the other side. |
| Incoming activities refused with `401` | The proxy alters `Host`, `Date`, `Digest` or `Signature`, or the server clock is more than five minutes off. |
| Deliveries pile up | `/admin/federation` shows the failing instances; deliveries retry for about three days. |
| Followers-only publications do not arrive | Both instances need `FEDERATION_RESTRICTED_ENABLED=true`, and the receiving instance needs the *Restricted* peer policy on the publishing side. |

## Sign-in through a provider fails

The callback URL registered at the provider must match exactly, and is built
from `FEDERATION_BASE_URL` (see [Identity providers](../features/identity-providers#callback-urls)).
Providers are read at boot: restart after changing their variables.

## Someone is locked out

- Lost second factor: `bin/rails users:reset_second_factor`, or the button in
  `/admin/accounts`.
- Lost password: the sign-in page's reset link (needs working mail).
- The operator locked out of `/admin`: reset the operator's factors from the
  server, sign in again and enrol a new factor.
