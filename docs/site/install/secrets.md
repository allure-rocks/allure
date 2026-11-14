# Secrets and keys

Generate every secret once, store it in `.env.production`, and keep a copy in
your password manager or secrets store. None of them can be recovered from the
running instance.

## `SECRET_KEY_BASE`

Signs session cookies and derives other application secrets.

```sh
openssl rand -hex 64
```

Changing it signs every member out.

## Active Record encryption keys

Three values encrypt sensitive columns at rest: federation private keys,
authenticator secrets, linked import accounts, push subscriptions, webhook
secrets and similar. Each is a 32-character random string:

```sh
for name in PRIMARY_KEY DETERMINISTIC_KEY KEY_DERIVATION_SALT; do
  echo "ACTIVE_RECORD_ENCRYPTION_${name}=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32)"
done
```

Paste the three lines into `.env.production`. Production refuses to boot when
one is missing.

::: danger Never rotate these casually
Data encrypted with a key can only be read with that key. If you lose or change
them, the encrypted columns become unreadable: members lose their second factor
and linked accounts, and the instance loses its federation keys.
:::

## Database password

```sh
openssl rand -hex 32
```

`ALLURE_DATABASE_PASSWORD` is used both to initialise PostgreSQL and by the
application. PostgreSQL only reads it when the `pgdata` volume is created: to
change it later, change it inside PostgreSQL first (`ALTER ROLE allure PASSWORD
…`), then in the file.

## Optional secrets

| Secret | How to generate |
|---|---|
| `METRICS_TOKEN` | `openssl rand -hex 32` |
| `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY` | `allure run --rm rails bin/rails push:vapid_keys` |
| Identity provider client secrets | From the provider's console |

Each is described in the [environment reference](../configuration/environment).
