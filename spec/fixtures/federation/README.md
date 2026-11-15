# Federation Fixtures

These small JSON documents pin the ActivityPub and WebFinger shapes used by the
M2 contract tests. They contain synthetic hosts and identities only; they are
not live endpoints and must not be used for network access. Contracts captured
from real Wanderer and Mastodon peers are an M5 concern.

`allure_note.json`, `allure_delete.json`, `allure_reject.json`, and
`allure_actor_delete.json` pin the strict Allure-to-Allure profile M5 receives:
a public Create with the `tag[]` metrics and `attachment[]` descriptors, a
publication Delete, a follow Reject, and an actor Delete carrying a Tombstone.
They are receiver inputs, not external-peer compatibility fixtures.

`allure_segment_note.json` pins the course Create profile
(`[devdoc:segments-federation]`): a `Note` on the dedicated
`/api/v1/segment/{shortuuid}` path with the `segment_kind`, `sport_slug`,
`match_tolerance`, and `average_grade` tags, a required GPX `Document`, and an
optional route-image `Image`.

`signature_headers.yml` pins the wire headers, body digests, and canonical
request inputs. It intentionally contains no private key or authorization
material. The public-key and cryptographic verification vectors shipped with
the completed M2 signature slice.
