# Maps contract

Workout and segment maps render a vector basemap through MapLibre GL JS. This
document defines the engine, the basemap provenance, the controller contract,
the theme pair, the controls, the track colouring, the hover synchronisation,
the direction chevrons and the display-only smoothing.

## 1. Outcome

1. Workout and segment maps render a vector basemap through MapLibre GL JS.
2. The basemap follows the user's light/dark theme with a real style pair
   instead of a CSS brightness filter.
3. The map carries zoom/compass, scale in the user's unit system, fullscreen,
   and the attribution required by the tile provider.
4. The track is coloured by elevation, speed or power along its length.
5. Hovering the elevation chart marks the corresponding point on the map, and
   hovering the map marks the corresponding point on the chart.
6. A single engine: no second mapping library in the dependency tree.

Non-goals, deliberately: 3D terrain, hillshade, globe projection, heatmap
overlays, client-side map export, and any change to the server-rendered route
PNG.

## 2. Locked decisions

| Decision | Choice | Rationale |
|---|---|---|
| Engine | MapLibre GL JS v6 | Vector rendering, native `[lon, lat]`, GPU line gradients |
| Cutover | Full replacement | One engine; no compatibility paths for behaviour that never shipped |
| Basemap | OpenFreeMap public instance | No API key, no registration, no cookies, no request limits, `access-control-allow-origin: *` |
| Light style | `https://tiles.openfreemap.org/styles/liberty` | |
| Dark style | `https://tiles.openfreemap.org/styles/dark` | A distinct dark style |
| Widgets | Navigation, Scale, Fullscreen, Attribution | `GeolocateControl` excluded from track maps; discover map only (`DESIGN.md` §20.6) |
| Track colouring | `line-gradient` over `line-progress` | |
| Hover sync | `window` `CustomEvent` keyed on cumulative distance | |

## 3. Basemap provenance and privacy

OpenFreeMap is a third-party public endpoint. Requesting tiles discloses
approximate route bounds and the viewer's IP address to it. This is recorded as
a trade-off, not a hidden behaviour: a privacy-strict deployment self-hosts the
tiles.

OpenFreeMap publishes weekly full-planet Btrfs and MBTiles images for
self-hosting, served under the same style-URL shape. Moving to a self-hosted
tileserver-gl or an OpenFreeMap self-host image is therefore a change to two
environment variables and no application code. That is the documented end state
for a privacy-strict deployment; the public instance is the interim default.

OpenFreeMap offers **no SLA**. The map must degrade gracefully when the style
fails to load: the `.allure-map` grid background and the track itself must still
render.

## 4. MapLibre v6 constraints

- **ESM only, no default export.** `import maplibregl from "maplibre-gl"` and
  `(await import("maplibre-gl")).default` both yield `undefined`. Every import
  must be named: `const { Map, Marker, NavigationControl } = await import("maplibre-gl")`.
- **WebGL2 is required**; WebGL1 support was removed.
- **The worker is loaded as a real URL, not a blob.** `worker-src blob:` is
  therefore **not** required. See §15.
- `GeoJSONSource.setData` no longer takes a second argument and no longer
  returns `this`, so it cannot be chained.
- `map.transform` was removed. Nothing here uses it.
- Style spec v25 logs legacy-expression problems as warnings rather than
  aborting the style load.

## 5. Attribution

Attribution is required by OpenFreeMap and by OpenStreetMap. MapLibre adds it
automatically from the style document. `AttributionControl` must not be
suppressed or replaced by a hand-written string; on the interactive map it is
added compact (`{ compact: true }`) so it does not cover the track, and expands
on click. The static route image keeps the non-compact control so the required
credit is baked into the PNG.

## 6. Preserved boundaries

- Owner route PNGs use MapLibre GL JS in a dedicated pinned-Chromium worker,
  producing 1600 x 900 images from an 800 x 450 CSS viewport at DPR 2. Geometry
  is passed directly to the browser process, not exposed through a render URL.
  The worker waits for tiles/fonts, captures markers and non-compact attribution,
  blocks resource origins outside the configured allowlist, and retries before
  using the existing raster/tile-less Ruby fallback.
- `Workouts::RouteImageRenderer` remains the offline fallback renderer.
  Publication PNGs are sanitized and immutable, and render asynchronously on
  the same worker with the MapLibre/OpenFreeMap style; raster and tile-less
  renderers are the fallbacks. A publication whose snapshot disables the
  `basemap` setting is rendered tile-less by intention, with no tile provider
  contacted; the same setting blanks the style on its interactive map.
- `@maplibre/maplibre-gl-native` remains rejected; Chromium runs the same
  MapLibre GL JS implementation as the interactive map and is isolated to the
  low-concurrency `route_images` worker image.
- Visibility gates, `Cache-Control: private, no-store`, and 404-not-500
  behaviour on `workout_tracks`, `workout_charts`,
  `workout_segment_selections`, `workout_route_images`, and `segment_tracks`.
- The repository-wide `[longitude, latitude]` convention. MapLibre is natively
  lon/lat, so no conversion boundary is introduced.
- Per-recording-segment separation. Each `TrackSegment` remains its own feature
  so pauses never draw a false connecting line.

## 7. The map controller

`map_controller.js`:

- dynamic, named import of MapLibre inside `connect()`;
- the style is fetched by the controller rather than handed to MapLibre as a
  URL, so a failure becomes a value to branch on and the track still draws over
  the grid background;
- waits on `style.load`, not `load`, so the route is not hostage to third-party
  tiles completing;
- inserts the track layer above every basemap geometry layer while the trailing
  label run stays above the route. The anchor is the first symbol layer that
  follows the last non-symbol layer, resolved at runtime rather than hardcoded
  (`app/frontend/lib/map_overlay_anchor.js`, shared with the static renderer);
- the selection highlight is a second GeoJSON source updated through `setData`;
- `#unwrapSegment` antimeridian handling, `#coordinatesForRange` offset
  walking, `#showState` overlay states, the `AbortController` on the track
  fetch, and per-segment separation are preserved;
- `disconnect()` survives the map being destroyed while the dynamic `import()`
  or the style-ready handler is still pending.

MapLibre 6's worker is a real URL built from a runtime template that no bundler
can resolve statically. `setWorkerUrl()` is called once with Vite's
`?worker&url` query; plain `?url` emits the worker without the sibling module it
imports and fails only in production. The map library is a separate chunk,
loaded only by pages that show a map.

## 8. Theme-aware basemap

- Initial style resolved from `document.documentElement.dataset.bsTheme`, which
  the layout renders server-side, so there is no flash of the wrong theme.
- Switching is driven by the existing `allure:theme-changed` window event
  emitted by `theme_controller.js`.
- `setStyle` discards user-added sources and layers. `setStyle(url, { transformStyle: (previous, next) => ... })`
  carries the track source, the selection source, and their layers across the
  swap.
- The view sends both style URLs, not the active one.

## 9. Core controls

`NavigationControl` with zoom and compass, `ScaleControl` with `unit:` derived
from `current_user.unit_system` through `data-map-unit-system-value`,
`FullscreenControl`, and `AttributionControl` per §5.

`GeolocateControl` is excluded from the track, segment and privacy-zone maps on
purpose: prompting for the viewer's location on a page about someone's location
history is the wrong default. The single exception is the discover map
(`DESIGN.md` §20.6): searching for courses *around me* is exactly what it is
for. There the control never prompts unsolicited — the map centres silently
only when the permission is already granted, and the explicit `Me localiser`
button is the only path to a prompt; the camera is capped at city zoom (12), and
without a granted position the map falls back to the start point of the viewer's
most recent workout.

Control labels are user-visible and go through MapLibre's `locale` option with
keys in both locale files. The scale bar reuses `units.symbols`, the same keys
the elevation chart uses. Dark-theme controls are overridden: MapLibre ships one
light control skin and exposes no custom properties, so the icons are inverted
and the attribution is restyled but kept legible.

## 10. Gradient track colouring

`line-gradient` paint driven by an `interpolate ["line-progress"]` expression.

- The gradient is per-feature, so one expression is built per segment feature;
  each has its own 0 to 1 progress range.
- The track is drawn as **one line layer per recording segment**, each filtered
  to its own `segment_index` against the single shared source. A single layer
  holding every segment would share one gradient expression, which is only
  correct when there is exactly one segment.
- Stops are downsampled to roughly 64 to 128, not one per point; downsample by
  distance while preserving elevation extrema. Stops must be strictly
  increasing; deduplicate after downsampling or MapLibre raises.
- `line-gradient` requires `lineMetrics: true` on the source and is incompatible
  with `line-dasharray`, which is unused here.
- The metric is normalised across the whole workout, not per segment, so a
  colour means the same altitude everywhere on the map.
- Metric arrays are realigned whenever a coordinate is dropped (the antimeridian
  filter), keeping geometry, elevation, distance and speed in step.
- `line-color` and `line-gradient` are mutually exclusive; switching metric
  clears one before setting the other.
- Anything without a usable metric falls back to the flat sport colour: a
  segment track (geometry only) and a metric that never varies. The selector
  hides itself unless at least two metrics are present.
- `line-progress` is geometric while `distance` is geodesic; stops are
  positioned by normalised cumulative distance, which matches closely enough for
  colouring.

## 11. Hover synchronisation

Synchronisation is keyed on **cumulative distance, not point index**. The public
chart endpoint omits `index`; only the owner-only selection endpoint sets
`include_index: true`. `distance` is always present, and the map side carries a
matching distance array, so distance works for every viewer with no further
endpoint change.

- Chart to map: the chart's pointer dispatches `allure:track-hover { distance }`;
  the map binary-searches its distance array and moves a hover marker.
- Map to chart: `map.on("mousemove", layer)` resolves the nearest point and the
  chart draws its cursor (a dotted rule and a ball).
- The chart is Apache ECharts: its pointer is read through the public `getZr()`
  events and `convertFromPixel`, and the cursor is a `graphic` layer placed with
  `convertToPixel`.
- Both sides degrade silently when the other is absent. A public viewer receives
  the chart without the map, because `map` visibility is stricter than
  `analysis`.
- Every event carries its origin and each controller ignores its own, so the two
  cannot echo each other. The map searches by binary search; a distance falling
  inside a recording gap matches no segment and clears the marker. The chart
  redraws on an animation frame and skips a repeated distance.

## 12. Power gradient and legend

Power joins the colour-by metrics (`TrackSeries::METRICS`):

- **Speed and power are binned.** Each colour stop takes the mean of the
  readings in its own slice of the route instead of one point, so a 1 Hz power
  trace or a GPS speed spike no longer paints static. Elevation keeps its
  sampled stops, which preserve summits.
- **Speed and power span their 2nd–98th percentile** (the chart's own
  `robustExtent`), so one sprint or one stop does not flatten the rest of the
  ride. Elevation keeps its true extremes.
- **A legend names the ramp's two ends** in the viewer's units, over the map's
  top-left corner, clear of the zoom controls, the scale and the attribution. It
  is hidden for the flat line.
- **The choice is remembered per kind of map** (`allure:map-colour` and
  `allure:map-colour:power-led`), the same split the elevation chart's secondary
  series uses.
- A power-led virtual ride offers *Puissance* first (`VIRTUAL-PLATFORMS.md`);
  every other map offers elevation, speed, then power. A metric absent from the
  track hides its option.

## 13. Direction chevrons

The sense of the route is carried by **full arrows with a 14 px shaft and an
open head**: a rounded 1.5 px track-coloured stroke over a subtle 2.8 px surface
halo, offset 12 screen pixels outside detected loops (right otherwise), one
about every 320 screen pixels along each recording segment. Direction is a
shape, never a colour, so it survives the flat track, the light-to-dark metric
gradient, both themes, and print.

- **Each ideal position owns a slot**, and the arrow is placed on the straightest
  candidate inside it: nine candidates spread over a third of the spacing on each
  side, scored by the angle between the direction before and after them, with
  candidates within 2° of the straightest considered equal and the closest to the
  slot centre winning. An arrow therefore never sits on a corner, while a
  straight noisy run keeps the regular spacing. A segment shorter than the first
  slot still gets one arrow at its straightest point.
  `Allure::Geometry::DirectionChevrons` and its JS mirror `chevronPlacements()`
  implement the same algorithm.
- They are derived from the drawn geometry alone. No track payload, snapshot,
  federated representation, or model validation changes: sanitized and received
  tracks stay geometry-only with `properties == ["segment_index"]`.
- On the live map they are one `symbol` layer over a dedicated GeoJSON source of
  **points carrying a map-space `angle` and an exterior `side`**, above the ink
  selection highlight. The icon points east, so the feature angle is the
  clockwise rotation from east; `icon-rotate` reads it and
  `icon-rotation-alignment: map` makes pan and rotation free. The spacing is a
  screen constant, so the controller derives the geographic spacing and
  clearance from the live zoom and recomputes the anchors on `zoomend` (and
  after a smoothing toggle); panning, rotating and theme swaps keep the same
  anchors.
- Repeated loop passes reuse the first pass's arrows. Each retained arrow marks
  its surrounding 320 px route window, sampled every 6.7 px into a spatial grid.
  Later anchors within approximately 13 px and 30° of that window are omitted,
  even across recording gaps. Reverse travel remains distinct.
- Fewer than three retained arrows means no direction overlay, globally after
  all recording segments and repeated passes have been processed. The live map
  recalculates the count on `zoomend`.
- A single pass around a loop already places its arrows outside. The pure
  `LoopExterior` / `loopExteriorSides` pair works on each projected recording
  segment with a 30 m closure tolerance, resamples at half that tolerance, and
  indexes prior visits in a spatial grid. Each closed excursion with perimeter
  at least eight times the tolerance and signed area larger than tolerance ×
  perimeter selects its exterior; earlier inner-loop assignments win over later
  enclosing excursions. Open approach/exit sections, retracing and ambiguous
  low-area shapes stay on the right. Recording gaps are never joined.
- The icon is a baked bitmap, not an SDF: its halo is the themed surface and its
  core the track colour. `icon-offset` selects `[0, -12]` or `[0, 12]` from the
  feature's `side` and rotates with the arrow. The controller re-registers it on
  `style.load` (and on `styleimagemissing` as a fallback) after a theme swap.
- The static MapLibre renderer projects the route on the fitted viewport and
  places the same point anchors; `Workouts::RouteImageRenderer` draws the arrows
  as SVG paths through `Allure::Geometry::DirectionChevrons`, so the raster and
  tile-less fallbacks carry them too. Arrows keep a clearance from the start dot
  and the checkered finish and never cross a recording gap.

## 14. Track smoothing

Display-only smoothing for GPS jitter: a rendering transform, never a data
change.

- `Allure::Geometry::Smoothing` and `app/frontend/lib/track_smoothing.js` are
  mirrors. Each point is replaced by a symmetric, triangular-weighted mean of the
  samples inside a distance window, with both endpoints fixed and the window
  capped at 61 samples so a stationary recording cannot make the filter
  quadratic. Levels are `light` (10 m half-window), `medium` (25 m) and `strong`
  (40 m); a coarse track whose samples are farther apart than the window is left
  untouched.
- **The point count is preserved.** Track payloads, course geometry and the map
  carry per-point metric arrays (distance, elevation, speed) aligned by index,
  and hover, selection and the colour ramp all read the same index. Smoothing
  never adds or removes a point, so none of them can silently misalign.
- Workout maps follow the account preference (`users.smooth_tracks` with
  `users.track_smoothing_level`, default off at medium). The map card header
  carries an options icon with an on/off checkbox that applies immediately and
  persists the account preference; a second map on the page (the publication
  snapshot) follows through `allure:smoothing-changed`. The intensity is chosen
  on `/settings/appearance`.
- Course maps and publication images are always smoothed at `medium`: segments
  are reusable corridors, not recordings, so the same window is right for every
  viewer. Workout route images stay unsmoothed — the recorded geometry is their
  contract; only their light/dark variant follows the viewer's picture-theme
  preference (`DESIGN.md` §15.4).
- The static renderer smooths before its RDP simplification, so a card image
  gets the same line as the live map; the Ruby basemap and tile-less fallbacks
  apply the same module before projection.
- No payload, snapshot, federated representation, privacy filter, metric, or
  stored geometry changes. Smoothing runs after authorization and sanitization,
  and the fixed endpoints mean a masked departure or arrival cannot be
  reconstructed.

## 15. Content Security Policy

The policy is active (`config/initializers/content_security_policy.rb`), and
`Allure::ContentSecurityPolicy` adds the map hosts per request. It needs:

- `connect-src` including the tile origin, for style, glyph, sprite, and vector
  tile requests;
- `img-src` including the tile origin, for the Natural Earth raster layer
  referenced by the OpenFreeMap styles.

MapLibre's own documented requirement is `worker-src 'self'` and
`img-src data: blob: 'self'`. `worker-src blob:` is **not** needed: the worker
is bundled and served from our own origin, so the worker URL is same-origin.
Blob workers only apply to loading MapLibre cross-origin from a CDN.

## 16. Out of scope

- 3D terrain, hillshade, globe projection, heatmap overlays.
- Client-side map export.
- Any change to the server-rendered route PNG contract beyond the renderer.
