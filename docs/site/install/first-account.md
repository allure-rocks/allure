# First account

## Create it

```sh
allure run --rm rails bin/rails users:create
```

The task asks for a username, an e-mail address and a password, without
echoing the password or leaving it in your shell history. Usernames are
permanent: with federation they become part of the account's address
(`@you@allure.example.org`).

## Make it the operator

One account — the **operator** — may open the administration console at
`/admin`: background jobs, federation controls, publications, accounts,
invitations, imports, diagnostics and the audit log. Name it with:

```sh
INSTANCE_OPERATOR_USERNAME=you
```

Add that line to `.env.production` and apply it with `allure up -d`. While it is
unset, no account is the operator.

## Set up two-step verification

Every account with a password must add a second factor — an authenticator app,
a passkey, or recovery codes — within a grace period (14 days by default,
`AUTH_2FA_GRACE_DAYS`). **The operator has no grace period**: on the first
sign-in, the operator is asked to set one up before anything else. Do it from
the “Two-step verification” card of the security settings (`/settings/security`),
and store the recovery codes safely.

If you lose every factor, remove them from the server and enrol again:

```sh
allure run --rm -e USERNAME=you rails bin/rails users:reset_second_factor
```

## Invite the next members

Registration is closed in production. To let someone create an account, send
them a single-use link bound to their e-mail address:

```sh
allure run --rm -e EMAIL=friend@example.org rails bin/rails users:invite
```

| Variable | Meaning |
|---|---|
| `EMAIL` | The address the invitation is bound to (asked interactively when absent). |
| `NAME` | An optional display name to pre-fill. |
| `EXPIRES_IN_DAYS` | Validity in days, `7` by default. |

The task prints the link; send it yourself. Once you are signed in as the
operator, you can also issue and revoke invitations from `/admin`. See
[Registration and invitations](../configuration/registration) for the other
options.
