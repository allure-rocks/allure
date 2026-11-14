# Weather

Members who opt in see the historical weather of each activity: temperature,
wind and its direction relative to the route, precipitation and conditions,
hour by hour. A publishing profile may also share a summary.

## What leaves the instance

Only for members who opt in at `/settings/weather`, and only for outdoor
activities with positions:

- one point at the start, one at each whole hour and one at the finish,
  **rounded to a 0.1° grid** (about 11 km) with an elevation rounded to 10 m;
- usually a single request per activity.

Members can withdraw consent and delete their stored weather from the same
page.

## Provider

Allure uses [Open-Meteo](https://open-meteo.com): the historical-forecast API
for recent activities and the ERA5 archive for older ones. Its free API is for
**non-commercial use** with a daily limit. For commercial use, take an
Open-Meteo plan (set its `customer-…` URLs and `WEATHER_API_KEY`) or run
Open-Meteo yourself and point the two URLs at it.

## Configuration

```sh
WEATHER_ENABLED=true
# Optional:
# WEATHER_FORECAST_URL=https://historical-forecast-api.open-meteo.com
# WEATHER_ARCHIVE_URL=https://archive-api.open-meteo.com
# WEATHER_FORECAST_SINCE=2022-01-01
# WEATHER_API_KEY=
# WEATHER_REQUESTS_PER_SECOND=2
# WEATHER_MAX_REQUESTS_PER_DAY=5000
```

Activities starting on or after `WEATHER_FORECAST_SINCE` use the forecast
endpoint, older ones the archive.

## Budget and failures

- Only one weather job runs at a time on the whole instance.
- `WEATHER_MAX_REQUESTS_PER_DAY` caps requests over any 24 hours; when it is
  spent, work waits and resumes hourly.
- `429`, `5xx` and timeouts are retried five times; every 15 minutes a recovery
  job retries recent failures and stale pending work.

## Existing activities

After enabling it, queue *Weather* in `/admin/jobs` to fetch it for consenting
members' past activities. Members can also queue their own from
`/settings/data`.

## Metrics

`allure_weather_requests_total{endpoint,result}` and `allure_workout_weathers`.
