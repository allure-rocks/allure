import { DIRECTION_IMAGE_ID, chevronPlacements, directionFeatureCollection, directionLayer, ensureDirectionImage } from "./direction_chevrons.js";
import { overlayAnchorLayerId } from "./map_overlay_anchor.js";
import { smoothCoordinates, validSmoothingLevel } from "./track_smoothing.js";
import { LOOP_CLOSURE_METRES } from "./loop_exterior.js";
import { WORLD_LAYER_ID, worldStyle } from "./virtual_world.js";

const TRACK_SOURCE = "allure-static-route";
const TRACK_LAYER = "allure-static-route-line";
const DIRECTION_SOURCE = "allure-static-direction";
const FIT_PADDING = 32;
const DEFAULT_TIMEOUT_MS = 30_000;
const MAX_POINTS = 2_000;
// The surface each PNG is drawn for: the light render sits on the application's
// light sunken surface, the dark render on the dark body background
// (DESIGN.md §15.4). The marker ring and the chevron halo both use it, so the
// two variants differ only by their surface, never by the track or the
// direction arrows.
const SURFACES = Object.freeze({ light: "#f4f6fa", dark: "#171717" });
// The marker ring and the chevron halo: white on the light PNG (as the Ruby
// renderer draws them), the dark surface on the dark PNG, so the track and the
// arrows stay legible on whatever lies under them.
const RINGS = Object.freeze({ light: "#ffffff", dark: "#171717" });
const THEMES = Object.freeze(Object.keys(SURFACES));

export async function renderStaticRoute({
  container,
  segments,
  lineColour,
  styleUrl,
  virtualBasemap,
  theme,
  maplibre,
  workerUrl,
  timeoutMs = DEFAULT_TIMEOUT_MS,
}) {
  if (!(container instanceof HTMLElement)) throw new Error("A map container is required");
  if (!maplibre?.Map || !maplibre?.Marker) throw new Error("MapLibre GL JS is required");
  if (!workerUrl) throw new Error("A MapLibre worker URL is required");

  const route = normalizeRoute({ segments, lineColour, styleUrl, virtualBasemap, theme });
  maplibre.setWorkerUrl(workerUrl);
  container.style.background = route.surface;

  let map;
  const errors = [];
  const markers = [];

  try {
    map = new maplibre.Map({
      container,
      style: route.style,
      interactive: false,
      attributionControl: false,
      fadeDuration: 0,
      center: [0, 0],
      zoom: 0,
    });
    map.addControl(new maplibre.AttributionControl({
      compact: false,
      customAttribution: route.attribution || undefined,
    }), "bottom-right");
    // Some third-party styles reference optional patterns that are absent from
    // their sprite. A transparent pixel preserves the rest of the style while
    // keeping genuine tile, glyph, sprite, and network failures fatal.
    map.on("styleimagemissing", ({ id }) => {
      if (id === DIRECTION_IMAGE_ID) {
        ensureDirectionImage(map, directionImageOptions(route));
        return;
      }
      if (!map.hasImage(id)) map.addImage(id, { width: 1, height: 1, data: new Uint8Array(4) });
    });
    map.on("error", (event) => errors.push(event.error ?? new Error("MapLibre resource failed")));

    await bounded(waitForEvent(map, "style.load", () => styleParsed(map)), timeoutMs, "map style");
    throwMapErrors(errors);

    map.addSource(TRACK_SOURCE, {
      type: "geojson",
      data: featureCollection(route.segments),
    });
    map.addLayer({
      id: TRACK_LAYER,
      type: "line",
      source: TRACK_SOURCE,
      layout: { "line-cap": "round", "line-join": "round" },
      paint: { "line-color": route.lineColour, "line-width": 4 },
    }, overlayAnchorLayerId(map.getStyle().layers));

    markers.push(addMarker(maplibre, map, route.segments[0][0], "start", route.ring));
    const finalSegment = route.segments[route.segments.length - 1];
    markers.push(addMarker(maplibre, map, finalSegment[finalSegment.length - 1], "finish", route.ring));

    const bounds = new maplibre.LngLatBounds();
    route.segments.forEach((segment) => segment.forEach((point) => bounds.extend(point)));
    map.fitBounds(bounds, { padding: FIT_PADDING, maxZoom: 16, animate: false });

    // The chevron slots are a screen constant, so the anchors are computed on
    // the fitted viewport rather than laid out by MapLibre along the line.
    map.addSource(DIRECTION_SOURCE, { type: "geojson", data: directionCollection(map, route.segments) });
    ensureDirectionImage(map, directionImageOptions(route));
    map.addLayer(directionLayer({ source: DIRECTION_SOURCE }), overlayAnchorLayerId(map.getStyle().layers));

    await bounded(waitForEvent(map, "idle", () => map.loaded()), timeoutMs, "map tiles");
    await bounded(document.fonts.ready, timeoutMs, "document fonts");
    await bounded(waitForStableFrames(map, errors), timeoutMs, "stable map frames");
    throwMapErrors(errors);
    // An image source has no tiles to wait for; `loaded()` above already
    // covers it. Only a tile basemap gets the stricter check.
    if (!route.virtualBasemap && typeof map.areTilesLoaded === "function" && !map.areTilesLoaded()) {
      throw new Error("MapLibre did not finish loading all visible tiles");
    }

    return { map, markers };
  } catch (error) {
    markers.forEach((marker) => marker.remove());
    map?.remove();
    throw error;
  }
}

export function validateStaticRouteInput(input) {
  return normalizeRoute(input);
}

export function staticRouteResourceAllowed(value, { localOrigin, styleUrl, allowedOrigins = [] }) {
  const url = new URL(value);
  if (url.origin === localOrigin) return true;

  const approved = new Set(allowedOrigins);
  let style = null;
  if (styleUrl) {
    style = new URL(styleUrl);
    approved.add(style.origin);
  }
  if (style?.protocol === "https:" && url.protocol !== "https:") return false;
  return new Set(["http:", "https:"]).has(url.protocol) && approved.has(url.origin);
}

function normalizeRoute(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new Error("Input must be a JSON object");
  }

  if (!/^#[0-9a-f]{6}$/i.test(input.lineColour ?? "")) {
    throw new Error("lineColour must be a six-digit hexadecimal colour");
  }

  let styleUrl;
  const theme = normalizeTheme(input.theme);
  const virtualBasemap = normalizeVirtualBasemap(input.virtualBasemap);
  if (!virtualBasemap) {
    try {
      styleUrl = new URL(input.styleUrl);
    } catch {
      throw new Error("styleUrl must be an absolute HTTP(S) URL");
    }
    if (!new Set(["http:", "https:"]).has(styleUrl.protocol) || styleUrl.username || styleUrl.password) {
      throw new Error("styleUrl must be an absolute HTTP(S) URL");
    }
  }

  if (!Array.isArray(input.segments) || input.segments.length === 0) {
    throw new Error("segments must contain at least one recording segment");
  }

  let previousLongitude;
  let previousUnwrapped;
  const segments = input.segments.map((segment) => {
    if (!Array.isArray(segment) || segment.length < 2) {
      throw new Error("Each recording segment must contain at least two points");
    }

    return segment.map((point) => {
      if (!Array.isArray(point) || point.length !== 2 ||
          !Number.isFinite(point[0]) || !Number.isFinite(point[1]) ||
          point[0] < -180 || point[0] > 180 || point[1] < -90 || point[1] > 90) {
        throw new Error("Route points must be finite [longitude, latitude] pairs");
      }

      let longitude = point[0];
      if (previousLongitude !== undefined) {
        longitude = previousUnwrapped + normalizedLongitudeDelta(longitude - previousLongitude);
      }
      previousLongitude = point[0];
      previousUnwrapped = longitude;
      return [longitude, point[1]];
    });
  });

  const allowedOrigins = Array.isArray(input.allowedOrigins) ? input.allowedOrigins.map((value) => {
    let origin;
    try {
      const url = new URL(value);
      if (!new Set(["http:", "https:"]).has(url.protocol) || url.username || url.password) throw new Error();
      origin = url.origin;
    } catch {
      throw new Error("allowedOrigins must contain absolute HTTP(S) origins");
    }
    return origin;
  }) : [];

  const smoothing = normalizeSmoothing(input.smoothing);
  const drawn = smoothing === null ? segments : segments.map((segment) => smoothCoordinates(segment, { level: smoothing }));

  return {
    segments: simplifyRoute(drawn),
    lineColour: input.lineColour,
    styleUrl: styleUrl?.href ?? null,
    style: virtualBasemap ? worldStyle(virtualBasemap, theme) : styleUrl.href,
    virtualBasemap,
    attribution: virtualBasemap?.attribution ?? null,
    allowedOrigins,
    smoothing,
    theme,
    surface: SURFACES[theme],
    ring: RINGS[theme],
  };
}

// A virtual world's map image, handed over by the Ruby renderer as a data URL
// so the renderer needs no network and no origin exception (docs/dev/VIRTUAL-PLATFORMS.md).
function normalizeVirtualBasemap(value) {
  if (value === undefined || value === null) return null;
  if (typeof value !== "object" || Array.isArray(value)) {
    throw new Error("virtualBasemap must be an object");
  }
  if (!/^data:image\/(webp|png);base64,[A-Za-z0-9+/=]+$/.test(value.image ?? "")) {
    throw new Error("virtualBasemap.image must be a base64 image data URL");
  }
  if (!/^#[0-9a-f]{6}$/i.test(value.background ?? "")) {
    throw new Error("virtualBasemap.background must be a six-digit hexadecimal colour");
  }
  if (value.darkBackground !== undefined && !/^#[0-9a-f]{6}$/i.test(value.darkBackground ?? "")) {
    throw new Error("virtualBasemap.darkBackground must be a six-digit hexadecimal colour");
  }
  if (!Array.isArray(value.coordinates) || value.coordinates.length !== 4 ||
      value.coordinates.some((pair) => !Array.isArray(pair) || pair.length !== 2 ||
        !Number.isFinite(pair[0]) || !Number.isFinite(pair[1]) ||
        pair[0] < -180 || pair[0] > 180 || pair[1] < -90 || pair[1] > 90)) {
    throw new Error("virtualBasemap.coordinates must contain four [longitude, latitude] corners");
  }

  return {
    image: value.image,
    coordinates: value.coordinates.map((pair) => [pair[0], pair[1]]),
    background: value.background,
    darkBackground: typeof value.darkBackground === "string" ? value.darkBackground : value.background,
    attribution: typeof value.attribution === "string" ? value.attribution : "",
  };
}

// The render surface. Absent and null mean the historical light PNG, so older
// payloads and direct CLI use keep their behaviour.
function normalizeTheme(value) {
  if (value === undefined || value === null || value === "") return "light";
  if (!THEMES.includes(value)) throw new Error("theme must be light or dark");
  return String(value);
}

// Display-only smoothing level. Absent, null and "off" all mean the recorded
// geometry, which is what workout images use; course images pass "medium".
function normalizeSmoothing(value) {
  if (value === undefined || value === null || value === "off") return null;
  if (!validSmoothingLevel(value)) throw new Error("smoothing must be off, light, medium or strong");
  return String(value);
}

function normalizedLongitudeDelta(delta) {
  while (delta > 180) delta -= 360;
  while (delta < -180) delta += 360;
  return delta;
}

function simplifyRoute(segments) {
  const minimum = segments.reduce((total, segment) => total + Math.min(segment.length, 2), 0);
  if (minimum > MAX_POINTS) throw new Error("Too many recording segments to render");
  if (segments.reduce((total, segment) => total + segment.length, 0) <= MAX_POINTS) return segments;

  let tolerance = 1e-7;
  while (Number.isFinite(tolerance)) {
    const simplified = segments.map((segment) => ramerDouglasPeucker(segment, tolerance));
    if (simplified.reduce((total, segment) => total + segment.length, 0) <= MAX_POINTS) return simplified;
    tolerance *= 2;
  }
  throw new Error("Route simplification did not converge");
}

function ramerDouglasPeucker(points, tolerance) {
  if (points.length <= 2) return points;

  const kept = new Array(points.length).fill(false);
  kept[0] = true;
  kept[points.length - 1] = true;
  const ranges = [[0, points.length - 1]];

  while (ranges.length > 0) {
    const [first, last] = ranges.pop();
    let farthest = -1;
    let distance = -1;
    for (let index = first + 1; index < last; index += 1) {
      const candidate = perpendicularDistance(points[index], points[first], points[last]);
      if (candidate > distance) {
        farthest = index;
        distance = candidate;
      }
    }
    if (distance <= tolerance) continue;

    kept[farthest] = true;
    ranges.push([farthest, last], [first, farthest]);
  }

  return points.filter((_, index) => kept[index]);
}

function perpendicularDistance(point, start, finish) {
  const dx = finish[0] - start[0];
  const dy = finish[1] - start[1];
  const lengthSquared = dx * dx + dy * dy;
  if (lengthSquared === 0) return Math.hypot(point[0] - start[0], point[1] - start[1]);

  const ratio = Math.min(1, Math.max(0,
    ((point[0] - start[0]) * dx + (point[1] - start[1]) * dy) / lengthSquared));
  return Math.hypot(
    point[0] - (start[0] + ratio * dx),
    point[1] - (start[1] + ratio * dy),
  );
}

function featureCollection(segments) {
  return {
    type: "FeatureCollection",
    features: segments.map((coordinates, index) => ({
      type: "Feature",
      geometry: { type: "LineString", coordinates },
      properties: { segment_index: index },
    })),
  };
}

// Projects the route onto the fitted viewport, places one chevron per slot on
// the straightest candidate, and returns the point features unprojected back
// to the map.
function directionCollection(map, segments) {
  const features = [];
  const covered = new Map();

  for (const segment of segments) {
    const projected = segment.map((coordinates) => {
      const point = map.project(coordinates);
      return [ point.x, point.y ];
    });

    const [longitude, latitude] = segment[0];
    const cosLatitude = Math.max(0.01, Math.cos(latitude * Math.PI / 180));
    const nearby = map.project([longitude + LOOP_CLOSURE_METRES / (111_319.49 * cosLatitude), latitude]);
    const closure = Math.hypot(nearby.x - projected[0][0], nearby.y - projected[0][1]);
    chevronPlacements(projected, { covered, closure }).forEach((placement) => {
      const coordinates = map.unproject([ placement.x, placement.y ]);
      features.push({
        type: "Feature",
        properties: { angle: placement.angle, side: placement.side },
        geometry: { type: "Point", coordinates: coordinates.toArray() },
      });
    });
  }

  return directionFeatureCollection(features);
}

function addMarker(maplibre, map, coordinates, kind, ring) {
  const element = document.createElement("div");
  element.className = `route-marker route-marker--${kind}`;
  element.style.borderColor = ring;
  element.setAttribute("aria-label", kind === "start" ? "Start" : "Finish");
  return new maplibre.Marker({ element }).setLngLat(coordinates).addTo(map);
}

// The halo sits under the track-coloured stroke; it takes the PNG's ring
// colour so the arrows stay legible in both variants (white on the light PNG,
// the dark body background on the dark PNG).
function directionImageOptions(route) {
  return { surface: route.ring, track: route.lineColour, devicePixelRatio: window.devicePixelRatio };
}

function styleParsed(map) {
  try {
    return map.isStyleLoaded() && Array.isArray(map.getStyle()?.layers);
  } catch {
    return false;
  }
}

function waitForEvent(map, eventName, ready) {
  if (ready()) return Promise.resolve();
  return new Promise((resolve) => map.once(eventName, resolve));
}

async function waitForStableFrames(map, errors) {
  for (let frame = 0; frame < 3; frame += 1) {
    map.triggerRepaint();
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    throwMapErrors(errors);
    if (!map.loaded()) await waitForEvent(map, "idle", () => map.loaded());
  }
}

function throwMapErrors(errors) {
  if (errors.length === 0) return;
  const error = errors[0];
  throw new Error(`MapLibre failed to load a resource: ${error?.message ?? String(error)}`);
}

function bounded(promise, timeoutMs, subject) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`Timed out waiting for ${subject}`)), timeoutMs);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}
