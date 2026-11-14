# Upgrading

## The usual procedure

```sh
git fetch --tags
git checkout <new-release-tag>
allure pull
allure up -d
```

Set `ALLURE_IMAGE` and `ALLURE_ROUTE_IMAGE_IMAGE` to the new tag in
`.env.production` before pulling. The published images are
`allurerocks/allure:<tag>` and `allurerocks/allure-route-image:<tag>`; to build
from source instead, run `allure build`.

Read the [changelog](https://github.com/allure-rocks/allure/blob/main/CHANGELOG.md)
first: a release that needs a step of its own says so below and there.

- The `rails` container applies pending migrations and reloads the reference
  catalogs (sports, equipment types) every time it starts. Workers restart on
  the new image.
- Derived data computed by an older version (analysis, route images, places…)
  is refreshed in the background; `/admin/jobs` shows what is outdated and
  offers the sweeps.
- Take a [backup](./backups) before upgrading.

To roll back, check out the previous tag and pull its images **only if the release
added no migration**; otherwise restore the backup taken before the upgrade.

## Automatic loop reconciliation

A one-off data migration schedules a fresh loop reconciliation on existing
positioned recordings, including recordings already processed by the previous
detector. It keeps loop identities until their efforts have been reassigned,
merges duplicate loops into the matching loop — the owner-renamed one when one
exists, otherwise the oldest — rebuilds detected laps and removes orphaned
loops. The kept loop retains its name and history. A loop the owner renamed
(`segments.renamed_at`, set by an explicit rename) is never removed by the
sweep; only the owner deletes it. Publications and original files do not
change.

The migration only invalidates detection markers and queues one sweep. The
worker processes recordings in batches of 100, at backlog priority behind new
imports. A fresh installation with no eligible recordings queues nothing.
Follow the pending count under **Administration → Jobs → Detected loops**.
There is normally no manual command to run. If the sweep fails, retry the job
there, or resume it with [`segments:loop_reuse`](../reference/cli).

The queue database must be available while the migration runs. If enqueueing
fails, startup fails visibly; restore queue connectivity and restart the web
container to retry the migration. Invalidation is retained, and rerunning the
migration or sweep is safe. Rolling back does not undo the derived-data
reconciliation or cancel jobs already queued.

## Automatic re-render of the Watopia and Paris route images

Zwift's October 2026 Watopia map adds the north-west archipelago its races start
on, and its July 2026 Paris map doubles the city. Both are new world images,
shipped with the application; a one-off data migration re-renders the owner
route images of the virtual activities drawn on those two worlds. Activities on
every other world keep their images: their artwork did not change, and the
renderer is the same.

The migration only invalidates those images and queues one sweep. The worker
processes them in batches of 100, at backlog priority behind new imports. A
fresh installation queues nothing. Follow the pending count under
**Administration → Jobs → Route images**. There is normally no manual command to
run; if the sweep fails, retry the job there, or resume it with
[`workouts:route_images`](../reference/cli). An activity that is published keeps
the image rendered at its publication: republish it to show the new map.

The queue database must be available while the migration runs. If enqueueing
fails, startup fails visibly; restart the web container to retry the migration.
Invalidation is retained, and rerunning the migration or sweep is safe.

## Automatic rebuild of the detected laps of teleport recordings

A virtual platform can move the athlete without moving them (a video route
returning to its start, a world change). The jump is not ground, so the smart
laps no longer count it as a climb: a one-off data migration rebuilds the
detected laps of every activity whose recording resumes 200 m or more from where
it stopped — a teleport, or a recording restarted elsewhere — and recomputes the
personal records, so the biggest-climb record no longer names a phantom climb.

The migration only enqueues one rebuild per affected activity; the worker
processes them in the background. A fresh installation queues nothing. Nothing
else changes: publications keep their snapshots, and an activity without a
teleport keeps the laps it had.

If enqueueing fails, startup fails visibly; restart the web container to retry
the migration. A rebuild is idempotent, so retrying it is safe.

## Release notes for operators

### After 0.8.7: the storage volume moves to `/rails/storage`

Up to 0.8.7, `docker-compose.production.yml` mounted the `allure_storage`
volume at `/app/storage`, while the application writes to `/rails/storage`.
Uploaded originals, route images, photos, avatars, exports and received media
were therefore kept **inside each container** — not shared between `rails`,
`worker` and `route-image-worker`, and lost whenever a container was recreated.
The volume itself stayed empty.

The new Compose file mounts the volume at `/rails/storage`. Before you run
`allure up -d` with it, rescue the files the current containers hold:

1. **Stop** the stack — do not use `down`, which deletes the containers and
   their files:

   ```sh
   allure stop
   ```

2. Copy each application container's files out. They hold different files, and
   file names never collide, so merge them into one directory:

   ```sh
   mkdir -p storage-rescue
   for service in rails worker route-image-worker; do
     docker cp "allure-production-${service}-1:/rails/storage/." storage-rescue/
   done
   ```

3. Copy them into the volume, owned by the application user (uid 1000):

   ```sh
   docker run --rm \
     -v allure-production_allure_storage:/target \
     -v "$PWD/storage-rescue:/source:ro" \
     alpine sh -c 'cp -a /source/. /target/ && chown -R 1000:1000 /target'
   ```

4. Check out the new release, pull and start as usual. Then make sure the
   files are visible from every container:

   ```sh
   allure exec rails ls /rails/storage
   allure exec worker ls /rails/storage
   ```

5. Keep `storage-rescue` until you have checked a few activities, photos and
   route images, then delete it.

If containers were already recreated before this upgrade, the files they held
are gone. Route images can be rendered again (this re-renders every one):

```sh
allure run --rm rails bin/rails workouts:regenerate_route_images
allure run --rm rails bin/rails segments:regenerate_route_images
```

Lost originals and photos cannot be recovered by Allure; members can import
the files again.
