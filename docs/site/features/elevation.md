# Terrain elevation

Some recordings carry no altitude (many phone apps, some watches) or a poor
one. With a terrain-elevation service, Allure can:

- fill in the elevation profile, ascent and descent of activities recorded
  without altitude;
- let a member switch any activity between the device's profile and the
  terrain's;
- give courses (segments) the terrain's profile.

## What leaves the instance

Positions along the route, sampled every 50 m by default (at most 4 000 points
per activity, in batches of 100). For activities, only members who opt in at
`/settings/elevation` are concerned. Courses use the terrain by default: a
public course is sampled without asking, a private or followers-only course
only if its owner opted in.

Running the service yourself keeps all of it on your server, which is why it is
the recommended setup.

## Running OpenTopoData

Allure speaks the [OpenTopoData](https://www.opentopodata.org) API. Run it next
to Allure following its documentation, with the dataset you need:

| Dataset | Coverage |
|---|---|
| `mapzen` | Worldwide, including the sea floor. A good default. |
| `srtm30m` | 60° S to 60° N, 30 m resolution. |

If you add it to the same Compose project (through an
[override](../install/overrides)) on the `backend` network, Allure reaches it
by its service name, and private addresses are allowed for this service.

## Configuration

```sh
ELEVATION_BASE_URL=http://opentopodata:5000
ELEVATION_DATASET=mapzen
# Optional tuning:
# ELEVATION_INTERPOLATION=bilinear
# ELEVATION_SAMPLE_METRES=50
# ELEVATION_REQUESTS_PER_SECOND=5
# ELEVATION_MAX_REQUESTS_PER_WORKOUT=40
```

Values are read when used: no restart is needed beyond `allure up -d` to pass
them. While `ELEVATION_BASE_URL` is unset, the feature is invisible to members.

## Existing data

New imports of opted-in members are enriched automatically. For the rest, use
the sweeps in `/admin/jobs` — *Estimated elevation* for activities and *Segment
elevation from the service* for courses — or:

```sh
allure run --rm rails bin/rails segments:terrain_elevation
```

Members can also queue their own activities from `/settings/data`.
Publications never change: a profile already shared stays as it was published.
