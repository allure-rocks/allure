# Backups and restore

An instance is three things. Lose any one and the others are of little use:

| What | Where | Why it matters |
|---|---|---|
| The databases | `pgdata` volume | Accounts, activities, publications, follows, the job queue. |
| The files | `allure_storage` volume | Original activity files, photos, route images, avatars, exports, received media. |
| The secrets | `.env.production` | Without `SECRET_KEY_BASE` and the three encryption keys, the encrypted columns — second factors, federation keys, linked accounts — cannot be read. |

Keep the secrets in your password manager; back up the other two regularly
and store the copies off the server.

## Databases

PostgreSQL holds four databases. Three are used:

| Database | Contents |
|---|---|
| `allure_production` | Everything the application stores. |
| `allure_production_queue` | Background jobs, scheduled and recurring. |
| `allure_production_cable` | Live-update messages. |
| `allure_production_cache` | Reserved; currently unused. |

Dump them in PostgreSQL's custom format while the stack runs:

```sh
mkdir -p backups
for db in allure_production allure_production_queue allure_production_cable; do
  allure exec -T db pg_dump -U allure -Fc "$db" > "backups/$db.dump"
done
```

A dump is consistent on its own, even with members using the instance.

## Files

Archive the storage volume from a throwaway container:

```sh
docker run --rm \
  -v allure-production_allure_storage:/storage:ro \
  -v "$PWD/backups:/backup" \
  alpine tar -czf /backup/storage.tar.gz -C /storage .
```

Take it right after the database dump. A file added in between is harmless; a
database row whose file is missing shows as a broken image or download until
the member imports again.

## Restore

On a fresh host, install as in the [quick start](../install/quick-start) with
the **same `.env.production`**, but do not create an account. Then:

1. Start the database only:

   ```sh
   allure up -d db
   ```

2. Restore each database:

   ```sh
   for db in allure_production allure_production_queue allure_production_cable; do
     allure exec -T db dropdb -U allure --if-exists "$db"
     allure exec -T db createdb -U allure "$db"
     allure exec -T db pg_restore -U allure -d "$db" --no-owner < "backups/$db.dump"
   done
   ```

3. Restore the files, owned by the application user (uid 1000):

   ```sh
   docker run --rm \
     -v allure-production_allure_storage:/storage \
     -v "$PWD/backups:/backup:ro" \
     alpine sh -c 'tar -xzf /backup/storage.tar.gz -C /storage && chown -R 1000:1000 /storage'
   ```

4. Start everything:

   ```sh
   allure up -d
   ```

   The `rails` container creates the unused cache database and applies any
   migration the restored data lacks.

Practise a restore on another machine once: a backup you never restored is a
hope, not a backup.

## The hostname

A restored instance must keep its `FEDERATION_BASE_URL`. Other instances know
your members by that address, and the federation keys inside the database are
bound to it.
