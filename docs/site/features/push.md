# Push notifications

Members using the **Allure iOS app** can receive their notifications as push
notifications. There is no browser push: without the app, members read
notifications in the web inbox, as they always can.

## How it works

Your instance sends standard Web Push messages to a **relay**, which forwards
them to Apple's push service for the app.

- The message is **encrypted for the device** (RFC 8291). The relay only sees
  an opaque payload, and Apple only that a notification was sent.
- Each message is **signed with your instance's VAPID key** (RFC 8292), so the
  relay knows which instance sent it. No account or shared secret is needed.
- The official relay, `https://push.allure.rocks`, is run by the app's
  publisher for every instance. If you build and sign your own iOS app, you
  need your own relay and list it in `PUSH_RELAY_ORIGINS`.

## Configuration

Generate a key pair once:

```sh
allure run --rm rails bin/rails push:vapid_keys
```

It prints two lines to paste into `.env.production`, then add a contact:

```sh
VAPID_PUBLIC_KEY=…
VAPID_PRIVATE_KEY=…
VAPID_SUBJECT=mailto:admin@example.org
# PUSH_RELAY_ORIGINS=https://push.allure.rocks
```

`VAPID_SUBJECT` is a `mailto:` address or an `https://` URL where the relay's
operator can reach you. Push is on once all three values are valid; members
then find an “On this iPhone” card in their notification settings inside the
app.

::: warning Keep the key pair
Each device registration is bound to your public key. Changing the pair
invalidates every registration: members must enable notifications again.
:::

## Delivery

Each notification is kept by the relay for up to a day. A subscription the
relay reports as gone, or bound to another key, is deleted; other failures are
retried with growing delays, and ten failures in a row delete the subscription.
A subscription belongs to one signed-in session and disappears with it.

## Metrics

`allure_push_deliveries_total{result}` (`delivered`, `gone`, `rejected`,
`failed`) and `allure_push_subscriptions`.
