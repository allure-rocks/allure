# Mail

Allure sends invitations, password resets, security notices (a new factor, a
new API token…), and notices that an export or an archive import is ready. It
needs working mail even on a single-person instance: password resets depend on
it.

## The stock relay

The stock stack includes `smtp-forwarder`, a Postfix container
([`boky/postfix`](https://github.com/bokysan/docker-postfix)) that only the
application can reach. It delivers each message directly to the recipient's
mail server. For that to work:

| Requirement | Why |
|---|---|
| Outbound port 25 open from the host | Direct delivery uses it; many cloud providers block it until asked. |
| A PTR record for the host's public address, equal to `SMTP_HOSTNAME` | Receivers reject mail from addresses without matching reverse DNS. |
| An SPF record for `MAILER_DOMAIN` that includes the host's address | Otherwise mail is marked as spoofed. |
| A DMARC record for `MAILER_DOMAIN` | Required by large providers for bulk senders, recommended for everyone. |

The relay does not sign with DKIM as configured; some receivers will rank its
mail lower.

The relevant variables are `MAILER_DOMAIN`, `MAILER_FROM`, `SMTP_HOSTNAME` and,
rarely, `SMTP_MYNETWORKS`; see the
[environment reference](./environment#mail).

## Relaying through a provider

If you cannot meet the requirements above, let the relay hand everything to
your mail provider's SMTP server. The relay image reads its upstream from its
own variables; set them in a [Compose override](../install/overrides):

```yaml
services:
  smtp-forwarder:
    environment:
      RELAYHOST: "[smtp.provider.example]:587"
      RELAYHOST_USERNAME: ${SMTP_RELAY_USERNAME:?}
      RELAYHOST_PASSWORD: ${SMTP_RELAY_PASSWORD:?}
```

Check the image's documentation for the options your provider needs. The
application keeps talking to `smtp-forwarder`, so nothing else changes.

## Checking

Request a password reset for your own account from the sign-in page, then read
the relay's log:

```sh
allure logs smtp-forwarder
```

`status=sent` means the receiving server accepted the message.
