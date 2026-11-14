# Instance identity

## The permanent part: `FEDERATION_BASE_URL`

`FEDERATION_BASE_URL` is the public origin of the instance —
`https://allure.example.org`. Every account's ActivityPub identity, every
published object and every signing key is derived from it, and the port is part
of it when it is not the default one.

Other instances store these addresses. Once your instance has federated,
changing the base URL does not move anything on their side: their follows keep
pointing at the old addresses. Pick the final hostname before you enable
federation, and keep `APP_HOST` equal to its host.

If the base URL must change before federation has been used — a test
installation that gets its real name, for example — the stored local identities
can be rewritten. Dry run first, then apply:

```sh
allure run --rm -e FROM=https://old.example.org rails bin/rails federation:rename_host
allure run --rm -e FROM=https://old.example.org -e APPLY=1 rails bin/rails federation:rename_host
```

## The presentation part

These variables only change what people see; they never affect identity, and
each one stays hidden while unset. Set them in `.env.production`.

| Variable | Where it shows |
|---|---|
| `INSTANCE_NAME` | Page titles, the footer, notifications, NodeInfo. Defaults to `Allure`. Nobody may register it as a username. |
| `INSTANCE_DESCRIPTION` | NodeInfo metadata and the web app manifest. |
| `INSTANCE_HOST_NAME` | The footer's “hosted by” line. |
| `INSTANCE_HOST_URL` | The link on that line; only an absolute `http(s)` URL is accepted. |
| `ALLURE_SOURCE_URL` | The About dialog's “Source code” link. Defaults to the upstream repository; point it at your own copy if you change the code, as the AGPL asks. |

## The operator

`INSTANCE_OPERATOR_USERNAME` names the one account allowed into `/admin`. See
[First account](../install/first-account#make-it-the-operator).
