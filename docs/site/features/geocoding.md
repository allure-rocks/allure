# Geocoding

With a geocoder, Allure names the places an activity passes through (the
departure, notable places, the arrival), names each segment by its
surroundings, and lets members search for a place when they draw a privacy
zone. Without one, those names are simply absent.

## What leaves the instance

Geocoding is an **instance-wide** choice: there is no per-member opt-in, so
enabling it sends **every member's route positions** to the provider.

- For each activity: a reverse lookup roughly every 100 m along the route, plus
  the start, the finish, climb summits and a few elevation samples, and up to 16
  searches for nearby town centres. A 50 km ride makes several hundred requests.
- For each segment: one lookup at its midpoint.
- For a privacy-zone search: the text the member typed, once per search.

Requests carry the header `User-Agent: Allure (toponymic markers;
https://geocoding.allure.rocks)` and no account information. Virtual activities
(Zwift, EXR…) are never geocoded. Results are stored with the activity and are
not requested again.

## Choosing a provider

Any [Nominatim](https://nominatim.org)-compatible service works. Prefer one you
run or have an agreement with:

- the public `nominatim.openstreetmap.org` allows **one request per second**
  and no heavy use — set `GEOCODING_REQUESTS_PER_SECOND=1` if you use it, and
  expect backlogs;
- a self-hosted Nominatim or a commercial provider can take the default budget
  of 10 requests per second, or more.

## Configuration

```sh
GEOCODING_BASE_URL=https://nominatim.example.org
GEOCODING_REQUESTS_PER_SECOND=10   # instance-wide budget
GEOCODING_CONCURRENCY=1            # jobs at once; read at boot
```

Each job paces itself to its share of the budget. Apply with `allure up -d`.

## Existing activities

New imports are geocoded automatically. For activities imported before you
enabled it, queue the sweeps from `/admin/jobs` (*Workout geocoding* and
*Segment places*) or run:

```sh
allure run --rm rails bin/rails workouts:toponymy
allure run --rm rails bin/rails segments:places
```

## When the provider is down

A `429`, a `5xx` or a timeout is retried five times with growing delays; the
activity is then marked failed. Every 15 minutes, a recovery job retries recent
failures (older than six hours, from activities of the last two days) and
anything left pending for two hours. Nothing else is affected: imports and
analysis never wait for geocoding.
