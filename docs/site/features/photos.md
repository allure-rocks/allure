# Photos

Members attach photos to their activities, place them along the route, and may
share them in a publication. Photos are **on by default**.

## Privacy

- The original stays private to its owner and is downloadable only by them.
- What is displayed and published is a re-encoded WebP with every metadata
  field (EXIF, GPS) removed.
- A published photo carries its position as a distance along the published
  route, never coordinates, and a photo taken inside a privacy zone is left out
  unless the member explicitly includes it.

## Limits

| Limit | Value |
|---|---|
| File size | 20 MB |
| Photos per activity | 20 |
| Dimensions | 12 000 px per side, 100 megapixels |
| Formats | JPEG, PNG, WebP; HEIC only if the image's libvips can decode it |
| Storage per account | `PHOTOS_QUOTA_MB`, 2 048 MB by default |

## Configuration

```sh
PHOTOS_ENABLED=true     # false hides photos everywhere
PHOTOS_QUOTA_MB=2048    # default quota of every account
```

To give one account a different quota, open it in `/admin/accounts` and set
its photo quota (empty returns to the default, `0` forbids new photos). The
change is audited.

## Storage and processing

Originals and their derivatives live in the `allure_storage` volume, so size
the disk for your members' quotas. Each upload is processed on the `photos`
queue of the `worker` container, two at a time; a recovery job picks up
interrupted processing every 15 minutes.

## Metrics

`allure_photos` (count) and `allure_photo_bytes` (storage used).
