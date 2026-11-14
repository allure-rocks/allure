# Registration and invitations

A production instance is **closed** by default: nobody can create an account
from the sign-in page, and the page says so.

## Invitations

An invitation is a single-use link bound to one e-mail address. It works while
registration is closed, and the account it creates is an ordinary account.

- From the server: `bin/rails users:invite`, described in
  [First account](../install/first-account#invite-the-next-members).
- From the administration console: `/admin` lists, issues and revokes
  invitations.

An invited member may sign up with a password or, when you have configured one,
through an identity provider.

## Opening registration

Set `ALLOW_REGISTRATION=true` in `.env.production` and run `allure up -d` to let
anyone create an account. Open it only if you are ready to moderate an open
instance: suspensions are in `/admin/accounts`.

## Usernames nobody can take

Usernames that clash with application routes, protocol endpoints or the
instance's own name (`INSTANCE_NAME`) are refused, and the username of a
deleted account is never handed out again.

## Second factor

Every password account must add a second factor within `AUTH_2FA_GRACE_DAYS`
(14 days by default) of setting its password. Accounts that sign in only
through an identity provider rely on the provider's own security. The operator
can reset a member's factors from `/admin/accounts`.
