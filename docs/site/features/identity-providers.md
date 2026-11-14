# Identity providers

Members can sign in with **Google**, **Sign in with Apple**, or one generic
**OpenID Connect** provider (Keycloak, Authentik, Dex, Zitadel…), alongside or
instead of a password. Each provider appears on the sign-in page once all its
variables are set. They are read at boot: restart after any change.

## How accounts are matched

- An identity is recognised by the provider's issuer and subject, **never by
  e-mail address**. A provider cannot sign into an account that has not linked
  it first.
- The provider must report a verified e-mail address.
- A new identity whose address already belongs to an account is refused; that
  member signs in with their password and links the provider from the security
  settings instead.
- A new identity creates an account only through the usual gate: open
  registration or a valid invitation. The member then chooses a username, and
  the account has no password.
- Members signing in through a provider are not asked for an Allure second
  factor — the provider's own sign-in counts. **The operator always is.**
- When the provider reports when the person authenticated (the ID token's
  `auth_time`, which Authentik, Keycloak and Apple send and Google does not),
  that moment is the session's proof of identity: a member signed in through
  a single sign-on session from days ago is asked to authenticate again before
  a sensitive action, exactly like a password session. The provider is then
  asked to authenticate the person again (`prompt=login`, `max_age=0`), and an
  answer that reuses the old authentication is refused.

## Callback URLs

Every URL derives from `FEDERATION_BASE_URL`, never from the request. With
`https://allure.example.org`:

| Provider | Register this URL |
|---|---|
| Google | `https://allure.example.org/auth/google/callback` |
| Apple | `https://allure.example.org/auth/apple/form_post` (the *Return URL*) |
| OpenID Connect | `https://allure.example.org/auth/oidc/callback` |

## Google

Create an OAuth client of type *Web application* in the Google Cloud console,
add the callback URL above, and set:

```sh
AUTH_GOOGLE_CLIENT_ID=…apps.googleusercontent.com
AUTH_GOOGLE_CLIENT_SECRET=…
```

Allure asks for `openid email profile`.

## Sign in with Apple

In the Apple developer account, create a *Services ID* with Sign in with Apple
enabled, add your domain and the Return URL above, and create a key for Sign in
with Apple. Then:

```sh
AUTH_APPLE_SERVICES_ID=org.example.allure.web
AUTH_APPLE_TEAM_ID=ABCDE12345
AUTH_APPLE_KEY_ID=XYZ987WVU6
AUTH_APPLE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nMIGT…\n-----END PRIVATE KEY-----"
```

The private key is the downloaded `.p8` file on a single line, each line break
written as `\n`.

## Generic OpenID Connect

The provider must support discovery (`/.well-known/openid-configuration`) and
the authorization-code flow; Allure uses PKCE and asks for
`openid email profile`. Register the client as **confidential** with the
callback URL above matched exactly, and sign ID tokens with an asymmetric key
(RS256, ES256…): a token signed with the client secret (HS256) is refused.

```sh
AUTH_OIDC_ISSUER=https://id.example.org/realms/allure
AUTH_OIDC_CLIENT_ID=allure
AUTH_OIDC_CLIENT_SECRET=…
AUTH_OIDC_LABEL="Example SSO"          # the button's name
AUTH_OIDC_REQUIRED_ACR=…               # optional
AUTH_OIDC_REQUIRED_AMR=…               # optional, e.g. mfa
```

With `AUTH_OIDC_REQUIRED_ACR`, Allure requests that authentication context and
refuses a sign-in whose ID token reports a different `acr` — the way to insist
that the provider's own multi-factor sign-in was used with a provider that
reports it there (Keycloak with a level-of-authentication mapping, for
instance). Some providers never vary `acr` — Authentik always reports
`goauthentik.io/providers/oauth2/default` — and list the methods used in
`amr` instead (RFC 8176): `AUTH_OIDC_REQUIRED_AMR=mfa` refuses a sign-in whose
token lacks that method. Either way the provider's flow must actually require
the factor; these settings only verify what it reports.

::: tip Authentik
Select a signing certificate on the provider (an empty *Signing Key* means
HS256), keep the *Subject mode* on the user's hashed ID, and force a second
factor in the authentication flow (Authenticator Validation stage, *Not
configured action: force the user to configure an authenticator*). With
`AUTH_OIDC_REQUIRED_AMR=mfa`, a member's very first sign-in — the one that
enrols the authenticator — reports `pwd` only and is refused once; the next
sign-in validates the device and succeeds.
:::

## The iOS companion

The companion signs in through the same providers in the system browser, then
hands the session back to the app; no extra callback URL is needed. It shows
Google only when Apple is enabled too, as the App Store requires.

For the companion's passkeys, list the app's identifiers:

```sh
IOS_APP_IDS=ABCDE12345.org.example.allure
```

They are served in `/.well-known/apple-app-site-association`, which answers 404
while the list is empty. The format is `TEAMID.bundle.id`, comma-separated; any
other value is ignored.

## Recovering accounts

| Situation | Command |
|---|---|
| A member lost every second factor | `allure run --rm -e USERNAME=name rails bin/rails users:reset_second_factor` |
| A password-less member wants a password | `allure run --rm -e USERNAME=name rails bin/rails users:send_password_setup` |

Both are also available, audited, from `/admin/accounts`.
