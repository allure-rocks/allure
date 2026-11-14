# Accounts

Members manage their own data. The operator steps in from
`/admin/accounts/:id`; every action there is audited.

## Suspending

**Suspend** (with a reason) signs the account out everywhere and refuses its
sign-ins. While suspended, nothing runs on its behalf: no notifications, push,
webhooks, remote synchronisation or automatic publishing. Its existing
publications stay online — withdraw them from `/admin/publications` if they
are the problem. **Reinstate** lifts the suspension.

You cannot suspend your own account.

## Second factors

**Reset two-step verification** removes every factor and closes every session;
the member sets up a new one at the next sign-in and is told by e-mail. The
same is available from the server:

```sh
allure run --rm -e USERNAME=name rails bin/rails users:reset_second_factor
```

## Data exports

Members download all their data themselves from their account settings: one
ZIP with their original files (re-importable on any Allure instance) and their
data as JSON and CSV, never a secret. One export runs at a time, at most one
per 24 hours, and it is deleted after seven days. The member is notified and
mailed when it is ready. Exports count in the storage volume while they exist.

## Deletions

A member deletes their own account from their account settings:

1. The account is **deactivated** for seven days: it is signed out elsewhere,
   its publications and courses are hidden, and nothing federates. The member
   can still sign in to cancel or download a last export.
2. After seven days, an hourly job purges it: the federated identity is
   withdrawn, then the activities and files, then the account. A final e-mail
   goes to its address.

The operator can **schedule** a deletion for an account (with the same seven
days) and **cancel** a scheduled one until the purge has started. Only the
operator can cancel a deletion the operator scheduled. You cannot delete your
own account.

A deleted username is never given out again.

## Invitations and passwords

- Invite: `/admin/invitations` or `bin/rails users:invite` — see
  [Registration and invitations](../configuration/registration).
- A member who signs in only through an identity provider and wants a
  password:

  ```sh
  allure run --rm -e USERNAME=name rails bin/rails users:send_password_setup
  ```
