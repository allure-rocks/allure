# Remote imports

Members can link an external account and have their activities imported
automatically. Each source is **off** until you enable it.

| Source | Variable | What it imports |
|---|---|---|
| Garmin Connect | `GARMIN_CONNECT_IMPORT_ENABLED=true` | Original FIT files, and gear. |
| EXR (virtual rowing) | `EXR_IMPORT_ENABLED=true` | FIT files of rowing sessions. |
| Withings | `WITHINGS_IMPORT_ENABLED=true` | TCX originals synthesized from the Health Mate series; positioned sessions by default. |
| Zwift | `ZWIFT_IMPORT_ENABLED=true` | Original FIT files of rides and runs, with their world. |

Members who are moving from Strava can always import the archive Strava sends
them; it needs no setting. A direct Strava connection is not available.

::: warning Unofficial integrations
Neither Garmin, EXR, Withings nor Zwift offers a public API for this. These
integrations are unofficial and not endorsed by the providers: they can stop
working whenever a provider changes something, and each provider's terms
apply. Review them before enabling a source.
:::

## What is stored

Members link from the account menu's « Connected services » entry (`/connections`).

- **Garmin Connect:** the e-mail and password (and the MFA code, if asked) are
  kept encrypted for at most five minutes while the sign-in runs, then
  discarded. Only Garmin's access and refresh tokens are kept, encrypted.
- **EXR:** the password is discarded the same way; only the site's
  remember-me cookie (valid five years) is kept, encrypted.
- **Withings:** the password is discarded the same way; only a day-long
  session is kept, encrypted.
- **Zwift:** the password is discarded the same way; only the refresh token
  (eight days, rotated on every refresh) and the athlete id are kept,
  encrypted. Zwift exposes only the newest 250 activities.

Health data (sleep, heart-rate variability…) is never imported.

## Synchronisation

- Every hour (at minute 5), linked accounts are checked for new activities.
- Members can also retrieve a date range or synchronise now.
- Work runs on the `remote_imports` queue of the `worker` container, one job at
  a time per linked account.
- Garmin answers `429` to repeated sign-ins; Allure never retries a sign-in on
  its own and asks the member to try again later. During a sync it sends at
  most one request per second and pauses a batch for 15 minutes on `429`.
- An expired or revoked link notifies its member.

To run one synchronisation pass now:

```sh
allure run --rm rails bin/rails remote_imports:sync
```

## Checking from your server

Garmin may refuse sign-ins coming from data-centre addresses. Check before
enabling it, with a Garmin account of your own (nothing is written to the
database):

```sh
allure run --rm -e GARMIN_EMAIL=you@example.org -e GARMIN_PASSWORD='…' \
  rails bin/rails garmin_connect:probe
```

`exr:probe` with `EXR_EMAIL` and `EXR_PASSWORD` does the same for EXR,
`withings:probe` with `WITHINGS_EMAIL` and `WITHINGS_PASSWORD` for Withings,
and `zwift:probe` with `ZWIFT_EMAIL` and `ZWIFT_PASSWORD` for Zwift. In
development, set those variables inside `dip sh`; `dip rails` does not
forward them.

## Operator controls

`/admin/imports/connections` lists every linked account by source and status —
never a credential nor the external account's name. **Revoke** wipes the
stored credentials, cancels queued imports, keeps what was already imported,
notifies the member, and is audited.

Disabling a source hides it from members and stops its jobs; existing links
stay stored until their members unlink them or you revoke them.

## Metrics

`allure_import_connections{provider,status}`,
`allure_import_connection_sync_age_seconds{provider}`,
`allure_import_connection_errors{provider}` and `allure_import_batches`.
