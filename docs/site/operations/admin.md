# The administration console

`/admin` is the operator's console, reached from the account menu's
**Administration** item.

- Only the account named by `INSTANCE_OPERATOR_USERNAME` may open it; anyone
  else gets a plain 404, as if it did not exist.
- The operator confirms a second factor every 15 minutes while using it.
- Every change made from it is recorded in the **audit log**, which nobody can
  edit.

## Panels

| Panel | Path | What you can do |
|---|---|---|
| Dashboard | `/admin` | Counts and trends — accounts, activities, publications, remote accounts, jobs, storage, imports — and the latest events. |
| Background jobs | `/admin/jobs` | Watch queues and workers, retry or discard failures, pause queues, run sweeps. See [Background jobs](./jobs). |
| Federation | `/admin/federation` | Delivery health, blocks, peer policies, media retries. See [Federation](../features/federation#the-federation-console). |
| Publications | `/admin/publications` | Every activity and course publication, by status and audience. **Withdraw** one that should not be public: it is removed locally and from the instances it reached. |
| Accounts | `/admin/accounts` | Search accounts; open one for its sessions, factors, sign-in methods, data export and deletion state. See [Accounts](./accounts). |
| Invitations | `/admin/invitations` | Issue a single-use invitation (the link is shown once and is not mailed) and revoke pending ones. |
| Imports | `/admin/imports` | Import batches by status and source, with the reason each failed entry was refused. |
| Service connections | `/admin/imports/connections` | Linked Garmin and EXR accounts, their last sync and error; revoke one. |
| System | `/admin/system` | Versions (Allure, Ruby, Rails, Solid Queue, PostgreSQL, PostGIS), database sizes, storage used, and which features are enabled. |
| Audit log | `/admin/events` | Every operator action and account deletion, newest first, filterable. |

The console shows counts and states, never activity contents, coordinates,
message payloads, keys or credentials.
