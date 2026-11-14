# CLI reference

Every task runs in a one-off container of the application image:

```sh
allure run --rm [-e NAME=value …] rails bin/rails <task>
```

Variables are passed with `-e`. Tasks that only *queue* work return at once;
the `worker` does the rest, and `/admin/jobs` shows the progress. Sweeps
accept `AFTER_ID=` to resume after the last id they reported.

## Accounts

| Task | Variables | Does |
|---|---|---|
| `users:create` | — (asks) | Creates an account interactively. |
| `users:invite` | `EMAIL`, optional `NAME`, `EXPIRES_IN_DAYS` (7) | Prints a single-use invitation link bound to the address. |
| `users:reset_second_factor` | `USERNAME` | Removes every second factor and closes every session. Audited. |
| `users:send_password_setup` | `USERNAME` | Mails a password-less account a link to set a password. Audited. |

## Federation

| Task | Variables | Does |
|---|---|---|
| `federation:rename_host` | `FROM`, `APPLY=1` | Rewrites stored local identities from `FROM` to the current `FEDERATION_BASE_URL`. Dry run without `APPLY=1`. |
| `federation:repair_relationships` | `APPLY=1` | Ends follows with remote accounts that were deleted or blocked. Dry run without `APPLY=1`. |

## Services

| Task | Variables | Does |
|---|---|---|
| `push:vapid_keys` | — | Prints a new VAPID key pair. |
| `remote_imports:sync` | — | Runs one synchronisation pass of every linked import account. |
| `funding:reconcile` | `SINCE` | Replays paid funding invoices if a webhook was lost or reordered, through every enabled provider. |
| `garmin_connect:probe` | `GARMIN_EMAIL`, `GARMIN_PASSWORD` (prompted when unset), optional `GARMIN_REGION` | Tries a Garmin Connect sign-in from this server; stores nothing. |
| `exr:probe` | `EXR_EMAIL`, `EXR_PASSWORD` (prompted when unset) | Tries an EXR sign-in from this server; stores nothing. |

## Sweeps

| Task | Variables | Queues |
|---|---|---|
| `workouts:rebuild` | `AFTER_ID` | Re-analysis of activities with outdated facts or analysis. |
| `workouts:toponymy` | `AFTER_ID` | Geocoding of activities missing it or outdated. |
| `workouts:heart_rate` | `AFTER_ID` | Heart-rate zones of recordings missing them or outdated. |
| `workouts:route_images` | — | Missing or outdated activity images. |
| `workouts:regenerate_route_images` | — | Every activity image, whatever its state. |
| `segments:route_images` | — | Missing or outdated course images. |
| `segments:regenerate_route_images` | — | Every course image. |
| `segments:loop_reuse` | `AFTER_ID` | Updated loop detection on positioned recordings, including those without a loop; discovers new circuits after two complete tours and recognizes an existing owner loop after one complete traversal, including after an approach. Publications are unchanged. |
| `segments:elevation_profiles` | `AFTER_ID` | Missing course elevation profiles. |
| `segments:terrain_elevation` | `AFTER_ID` | Terrain elevation of eligible courses (needs `ELEVATION_BASE_URL`). |
| `segments:places` | `AFTER_ID` | Place names of courses (needs `GEOCODING_BASE_URL`). |
| `best_efforts:backfill` | `AFTER_ID`, `SPORT` | Best efforts of every activity, or of one sport. |
| `best_efforts:rebuild` | `WORKOUT` | Best efforts of one activity, at once. |
| `laps:backfill` | `AFTER_ID` | Detected laps of every activity. |
| `laps:rebuild` | `WORKOUT` | Detected laps of one activity, at once. |

`WORKOUT` takes the activity's id as shown in its address.

## Database

| Task | Does |
|---|---|
| `db:prepare` | Creates missing databases and applies pending migrations. Runs at every start of `rails`. |
| `db:seed` | Loads the reference catalogs (sports, equipment types). Runs at every start of `rails`; safe to repeat. |
