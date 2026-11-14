# Federation

Federation lets members follow people on other Allure instances and receive
their publications, comments and reactions over
[ActivityPub](https://www.w3.org/TR/activitypub/). It is **off** until you turn
it on.

::: warning Allure to Allure only
Federation is implemented and tested between Allure instances. Mastodon and
other ActivityPub software can discover accounts, but their posts are not
accepted and the way they display Allure publications is not supported.
:::

## Before you turn it on

- **Choose the final hostname.** `FEDERATION_BASE_URL` becomes part of every
  account's permanent address (`@marie@allure.example.org`) and of every object
  other instances store. Changing it later breaks every follow; see
  [Instance identity](../configuration/instance).
- **Serve it over HTTPS** on that hostname. Production refuses to boot with an
  `http://` base URL.
- **Keep the clock in sync** (NTP). Signed requests more than five minutes off
  are refused.
- **Set the operator** (`INSTANCE_OPERATOR_USERNAME`), who manages blocks and
  peers.

## Turning it on

In `.env.production`:

```sh
FEDERATION_ENABLED=true
```

Then `allure up -d`. While it is off, every federation endpoint answers 404,
nothing is delivered or fetched, and members see no remote follow, profile or
note. Members still follow each other on the instance from `/people` and from
their profiles.

## What the reverse proxy must route

All of these are ordinary paths on the instance's hostname; a proxy that
forwards everything needs no change.

| Path | Purpose |
|---|---|
| `/.well-known/webfinger` | Account discovery (`acct:user@host`). |
| `/.well-known/nodeinfo`, `/nodeinfo/2.1`, `/nodeinfo/2.2` | Instance metadata. |
| `/users/:username` | The actor; its `outbox`, `followers`, `following` and `inbox` below it. |
| `/inbox` | The shared inbox. Bodies are limited to 1 MB. |
| `/api/v1/trail/:id`, `/api/v1/segment/:id`, `/api/v1/comment/:id` | Published objects and their `/media/…` files. |

The proxy must pass `Host`, `Date`, `Digest` and `Signature` through unchanged.

## Checking it

From any machine:

```sh
curl -s 'https://allure.example.org/.well-known/webfinger?resource=acct:you@allure.example.org'
curl -s -H 'Accept: application/activity+json' https://allure.example.org/users/you
```

The first returns a JSON document linking to `/users/you`; the second the
`Person` document with a public key. Then follow an account on another Allure
instance from `/people`: the request stays pending until the other side
accepts it, since every follow request is approved by hand.

## How delivery works

Publishing an activity creates one delivery per remote inbox, sent by the
`worker` container on the `federation` queue:

- at most five deliveries at once to the same instance;
- up to ten attempts, from five minutes apart doubling to a day apart;
- network errors, `429` and `5xx` are retried, other `4xx` answers are final;
- an inbox answering `410 Gone` is looked up once more, then dropped.

Received media (route images, GPX tracks, avatars) are downloaded on the
`federation_media` queue, checked against size and point limits, and served to
members from your instance only. A recovery job retries stuck work every five
minutes.

Incoming requests are limited to 60 per minute and 600 per hour per remote
instance; beyond that the sender gets `429` with `Retry-After`.

## Followers-only publications

Members can always publish for their followers: accepted followers on your
instance read those publications whatever the settings below. By default only
**public** publications leave the instance, though. To let followers-only
publications reach followers on other instances:

1. Set `FEDERATION_RESTRICTED_ENABLED=true` on your instance. The other
   instance must set it too.
2. In `/admin/federation`, give each trusted instance the **Restricted** peer
   policy (direct fetch, or shared inbox if it has one).

A followers-only publication is then delivered to accepted followers on
promoted instances only, and every later fetch of it or its media is checked
again against the follow. Unfollowing, refusing or blocking withdraws it and
purges the copy on the other side.

The recipients of a publication are decided when it is published: turning the
setting on does not send the followers-only publications made while it was
off. Turning it off stops new deliveries and refuses further fetches from other
instances.

## The federation console

`/admin/federation` shows counts only — never payloads, keys or coordinates:
inbox items, deliveries by status and by instance, failing instances, received
notes and media. It offers:

| Action | Effect |
|---|---|
| Block an instance / an account | Stops deliveries both ways (their requests get `403`), hides their profiles, ends follows, and withdraws what they sent. Unblocking restores nothing: they must publish again. |
| Peer policy | Sets what an instance may receive: *Public publications only* or *Restricted* (followers-only allowed). An instance never promotes itself; a new one starts as *unknown*, which receives public publications. |
| Retry failed downloads | Queues again the remote media that failed. |

Every action is recorded in the audit log.

## Maintenance tasks

```sh
# Moving to a new hostname before anyone federated with you (dry run, then APPLY=1).
allure run --rm -e FROM=https://old.example.org rails bin/rails federation:rename_host

# End follows with remote accounts that were deleted or blocked but left open.
allure run --rm rails bin/rails federation:repair_relationships
allure run --rm -e APPLY=1 rails bin/rails federation:repair_relationships
```

`federation:rename_host` does not tell other instances: anyone who already
followed your members must follow them again.

## Deleted accounts

When a member deletes their account, nothing federates during the seven-day
window. Then the instance withdraws their publications, sends a signed `Delete`
for the account to the instances that knew it, and answers `410 Gone` for the
actor from then on. Its signing key is destroyed once every pending delivery
has finished. The username is never given out again.

## Metrics

`/metrics` exports `allure_federation_*` families: inbox items, deliveries and
the age of the oldest open one, outbox events, received notes and courses,
media, follows, remote actors by peer policy, blocks, and inbox refusals by
reason.
