# Compose overrides

`docker-compose.production.yml` is part of the source, so you should not edit
it: your changes would conflict with the next release. Put local changes in an
override file instead and pass both files to Compose:

```sh
alias allure='docker compose --env-file .env.production -f docker-compose.production.yml -f compose.override.yml'
```

Compose merges the files: an `environment` key in the override is added to, or
replaces, the same key of the stock file.

## Why you may need one

The stock file passes to the containers only the variables it lists. The
[environment reference](../configuration/environment) marks each variable:

- **env file** — set it in `.env.production`, the stock file passes it on;
- **override** — the stock file does not pass it; set it in an override;
- **fixed** — the stock file sets a fixed value; change it only through an
  override, and only if you know why.

Most instances need no override for variables: registration, federation, the
operator and every optional service are set in `.env.production`. Overrides are
for tuning, such as `SMTP_ENABLE_STARTTLS`, `RAILS_MAX_THREADS` or
`ALLOWED_HOSTS`.

## Passing variables

The application runs in three containers, `rails`, `worker` and
`route-image-worker`, which must see the same configuration. Define the values
once with a YAML anchor and give them to all three:

```yaml
# compose.override.yml
x-allure-environment: &allure-environment
  SMTP_ENABLE_STARTTLS: ${SMTP_ENABLE_STARTTLS:-false}
  RAILS_MAX_THREADS: ${RAILS_MAX_THREADS:-3}

services:
  rails:
    environment: *allure-environment
  worker:
    environment: *allure-environment
  route-image-worker:
    environment: *allure-environment
```

The values themselves stay in `.env.production`:

```sh
SMTP_ENABLE_STARTTLS=true
```

Apply with `allure up -d`.

::: warning Never pass `ALLOWED_HOSTS` empty
An empty `ALLOWED_HOSTS` disables Rails' host check altogether. Only add it to
an override with a value, never as `${ALLOWED_HOSTS:-}`.
:::

## Publishing the port on the host

When the reverse proxy runs on the host rather than in a container, publish the
application port on the loopback interface only:

```yaml
services:
  rails:
    ports:
      - "127.0.0.1:3000:3000"
```

## Relaying mail through a provider

See [Mail](../configuration/mail#relaying-through-a-provider).
