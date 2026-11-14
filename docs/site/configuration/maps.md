# Maps and route images

## Interactive maps

Members' browsers draw maps with MapLibre from a **style document**: a JSON
file that names its own tile, font and sprite servers and carries the
attribution its provider requires. Allure only needs the style's URL, one per
theme:

| Variable | Default |
|---|---|
| `MAP_STYLE_URL` | `https://tiles.openfreemap.org/styles/liberty` |
| `MAP_STYLE_URL_DARK` | `https://tiles.openfreemap.org/styles/dark` |

[OpenFreeMap](https://openfreemap.org) needs no key and sets no cookie, but it
is a third party: loading tiles tells it roughly which area is on screen. For a
stricter setup, host your own tiles and point both variables at your styles.
When you set only `MAP_STYLE_URL`, the dark theme reuses it rather than falling
back to OpenFreeMap, so no route bounds reach a provider you meant to replace.

A URL must be absolute `http` or `https` and must not contain credentials: it
is handed to every browser.

## Route images

The `route-image-worker` renders a light and a dark picture of each activity
with the same MapLibre style, in a headless Chromium. If that fails after a few
attempts, it falls back to a raster basemap, then to a route drawn without a
basemap.

| Variable | Default | Purpose |
|---|---|---|
| `MAP_RASTER_TEMPLATE` | `https://tile.openstreetmap.org/{z}/{x}/{y}.png` | Raster tiles for the fallback and for the images of published activities. Must contain `{z}`, `{x}` and `{y}`. |
| `ROUTE_IMAGE_MAP_ORIGINS` | none | Extra origins the renderer may load from, comma-separated, when your style loads tiles, fonts or sprites from hosts other than its own. |
| `ROUTE_IMAGE_RENDER_TIMEOUT_MS` | `30000` | Time allowed for one rendering. |

The public OpenStreetMap tile servers have a
[usage policy](https://operations.osmfoundation.org/policies/tiles/); a busy
instance should use its own raster tiles.

Images are rendered once and stored. After changing the basemap, re-render the
existing ones:

```sh
allure run --rm rails bin/rails workouts:regenerate_route_images
allure run --rm rails bin/rails segments:regenerate_route_images
```

Published activities keep the image frozen at publication time.
