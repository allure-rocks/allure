# Quick start

This page installs Allure with the production Compose file shipped in the
repository. It takes about five minutes: the images are pulled from Docker Hub.

Every command below runs from the root of your checkout. To keep them short,
define an alias first:

```sh
alias allure='docker compose --env-file .env.production -f docker-compose.production.yml'
```

If you add a [Compose override](./overrides), append `-f` with your override file
to the alias.

## 1. Get the source

```sh
git clone https://github.com/allure-rocks/allure.git
cd allure
git checkout <release-tag>
```

Deploy a release tag rather than the default branch.

## 2. Write the environment file

```sh
cp production.env.example .env.production
chmod 600 .env.production
```

Keep `.env.production` out of version control. Compose refuses to start until
every required value is set:

| Variable | Value |
|---|---|
| `APP_HOST` | The public hostname only, without scheme or path: `allure.example.org`. |
| `FEDERATION_BASE_URL` | The public origin: `https://allure.example.org`. It becomes part of every account's permanent identity; see [Instance identity](../configuration/instance). |
| `SECRET_KEY_BASE` | A long random value. |
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`<br>`ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`<br>`ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | Three random values that encrypt secrets in the database. |
| `ALLURE_DATABASE_PASSWORD` | The PostgreSQL password. |
| `MAILER_DOMAIN`, `MAILER_FROM` | The sending domain and the `From` address. |
| `SMTP_HOSTNAME` | The hostname the mail relay announces. |

[Secrets and keys](./secrets) shows how to generate the random values. **Back
them up**: losing the encryption keys makes the encrypted data in the database
unreadable.

Everything else is optional and described in the
[environment reference](../configuration/environment).

## 3. Pull the images

Add the release tag you checked out to `.env.production`:

```sh
ALLURE_IMAGE=allurerocks/allure:<release-tag>
ALLURE_ROUTE_IMAGE_IMAGE=allurerocks/allure-route-image:<release-tag>
```

Then pull:

```sh
allure pull
```

`latest` is the default when neither variable is set, but a release tag is what
you want to run. To build from source instead, run `allure build`: it produces
`allure:production` and `allure:production-route-image`, and the same two
variables point at them.

## 4. Start

```sh
allure up -d
```

On its first start the `rails` container creates the databases, runs the
migrations and loads the reference catalogs. Follow it with:

```sh
allure logs -f rails
```

The application answers on port `3000` of the `rails` container once Puma
reports it is listening. Nothing is published on the host yet: put your
[reverse proxy](./reverse-proxy) in front of it.

## 5. Create your account

```sh
allure run --rm rails bin/rails users:create
```

Then name it the operator and finish the setup in
[First account](./first-account).

## Upgrading

```sh
git fetch --tags
git checkout <new-release-tag>
allure pull
allure up -d
```

Set `ALLURE_IMAGE` and `ALLURE_ROUTE_IMAGE_IMAGE` to the new tag in
`.env.production` before pulling. Read
[Upgrading](../operations/upgrading) first: some releases need a step of their
own.

If a start ever needs to be repeated by hand, the preparation is idempotent:

```sh
allure run --rm rails bin/rails db:prepare db:seed
```
