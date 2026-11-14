import { LOOP_CLOSURE_METRES, loopExteriorSides } from "./loop_exterior.js";

// Direction-of-travel arrows. The sense of a route is carried by a shape,
// never by colour, so it survives the flat track, the metric gradient, both
// themes, and print. The icon is baked (not an SDF) because its colours come
// from the live theme: re-registering it after a style swap is cheaper than
// repainting it on every theme change.
export const DIRECTION_IMAGE_ID = "allure-direction-chevron";
export const DIRECTION_LAYER_ID = "allure-direction-chevrons";

// Screen pixels between two chevron slots. Map, static renderer and Ruby
// renderer placement all use it.
export const CHEVRON_SPACING = 320;
export const CHEVRON_CLEARANCE = 24;
const MIN_DIRECTION_COUNT = 3;

// Candidates sampled inside one slot, mirrored by
// `Allure::Geometry::DirectionChevrons`.
const SLOT_SAMPLES = 9;

// Candidates within this many degrees of the straightest one count as equal,
// and the closest to the slot centre wins among them. A real trace is never
// perfectly straight, and without the tolerance the smallest jitter would make
// the anchors wander inside their slots.
const STRAIGHTNESS_TOLERANCE_DEGREES = 2;

// WebMercator pixels: the world is 512 px wide at zoom 0, and a degree of
// latitude is 111.3 km. The chevron slots are a screen constant, so the
// geographic spacing is derived from the live zoom.
const METRES_PER_PIXEL_AT_ZOOM_ZERO = 78_271.51696;
const METRES_PER_DEGREE = 111_319.49;

const CHEVRON_SIZE = 24;
// A surface halo under a thinner track-coloured stroke keeps the offset
// arrow readable on the basemap and on both themes. Both
// strokes are rounded so the glyph reads as one drawn mark, not a sticker.
const CHEVRON_HALO_STROKE = 2.8;
const CHEVRON_CORE_STROKE = 1.5;
const CHEVRON_DPR_LIMIT = 3;

// Local coordinates of a right-pointing arrow head: the anchor's angle is a
// clockwise rotation from east, and `icon-rotation-alignment: map` applies it
// to the glyph's east axis.
export const CHEVRON_POINTS = Object.freeze([
  Object.freeze({ x: 14.5, y: 8 }),
  Object.freeze({ x: 19, y: 12 }),
  Object.freeze({ x: 14.5, y: 16 }),
]);

// One chevron per slot of `spacing`, at the candidate whose incoming and
// outgoing directions disagree the least, so a chevron never sits on a corner.
// `points` is a planar `[x, y]` polyline (screen pixels, or a locally scaled
// lon/lat frame); the returned angle is clockwise from east in that frame.
export function chevronPlacements(points, { spacing = CHEVRON_SPACING, clearance = CHEVRON_CLEARANCE, covered = new Map(), closure = spacing / 24 } = {}) {
  const coordinates = Array.isArray(points) ? points : [];
  if (coordinates.length < 2) return [];

  const lengths = cumulativeLengths(coordinates);
  const total = lengths[lengths.length - 1];
  if (!(total > 0)) return [];

  const slotHalf = spacing / 3;
  const lookahead = spacing / 3;
  const placements = [];
  for (let distance = spacing / 2; distance < total; distance += spacing) {
    const placement = straightestPlacement(coordinates, lengths, total, distance, slotHalf, lookahead, clearance);
    if (placement) placements.push(placement);
  }

  // A trace shorter than the first ideal position still deserves one chevron.
  if (placements.length === 0 && total > 2 * clearance) {
    const placement = straightestPlacement(coordinates, lengths, total, total / 2, total / 2, lookahead, clearance);
    if (placement) placements.push(placement);
  }

  const sides = loopExteriorSides(coordinates, placements.map((placement) => placement.distance), { closure });
  placements.forEach((placement, index) => { placement.side = sides[index]; });

  // Cover a route window around each retained arrow, rather than only its
  // anchor: repeated laps need not land on the same slot centres. A spatial
  // grid keeps this linear in the number of arrows, even on long recordings.
  const tolerance = spacing / 24;
  return placements.filter((placement) => {
    const cellX = Math.floor(placement.x / tolerance);
    const cellY = Math.floor(placement.y / tolerance);
    for (let dx = -1; dx <= 1; dx += 1) {
      for (let dy = -1; dy <= 1; dy += 1) {
        const samples = covered.get(`${cellX + dx},${cellY + dy}`) || [];
        if (samples.some((sample) => Math.hypot(sample.x - placement.x, sample.y - placement.y) <= tolerance
          && Math.abs(((sample.angle - placement.angle + 540) % 360) - 180) < 30)) return false;
      }
    }
    for (let index = 0; index <= 48; index += 1) {
      const at = Math.max(0, Math.min(total, placement.distance - spacing / 2 + index * spacing / 48));
      const [x, y] = pointAt(coordinates, lengths, at);
      const key = `${Math.floor(x / tolerance)},${Math.floor(y / tolerance)}`;
      if (!covered.has(key)) covered.set(key, []);
      covered.get(key).push({ x, y, angle: placementAngle(coordinates, lengths, at, total, lookahead) });
    }
    return true;
  }).map(({ x, y, angle, side }) => ({ x, y, angle, side }));
}

function cumulativeLengths(points) {
  const lengths = [0];
  for (let index = 1; index < points.length; index += 1) {
    lengths.push(lengths[index - 1] + Math.hypot(
      points[index][0] - points[index - 1][0],
      points[index][1] - points[index - 1][1],
    ));
  }
  return lengths;
}

function straightestPlacement(coordinates, lengths, total, center, slotHalf, lookahead, clearance) {
  const low = Math.max(center - slotHalf, clearance);
  const high = Math.min(center + slotHalf, total - clearance);
  if (high < low) return null;

  const candidates = [];
  for (let index = 0; index < SLOT_SAMPLES; index += 1) {
    const ratio = index / (SLOT_SAMPLES - 1);
    const at = low + (high - low) * ratio;
    candidates.push({ at, turn: turnDegrees(coordinates, lengths, at, total, lookahead) });
  }

  const bestTurn = Math.min(...candidates.map((candidate) => candidate.turn));
  const at = candidates
    .filter((candidate) => candidate.turn <= bestTurn + STRAIGHTNESS_TOLERANCE_DEGREES)
    .reduce((closest, candidate) => (
      Math.abs(candidate.at - center) < Math.abs(closest.at - center) ? candidate : closest
    ))
    .at;

  const [x, y] = pointAt(coordinates, lengths, at);
  return { x, y, angle: placementAngle(coordinates, lengths, at, total, lookahead), distance: at };
}

function turnDegrees(coordinates, lengths, at, total, lookahead) {
  const before = directionBetween(coordinates, lengths, Math.max(at - lookahead, 0), at);
  const after = directionBetween(coordinates, lengths, at, Math.min(at + lookahead, total));
  if (!before || !after) return 0;

  const cross = before[0] * after[1] - before[1] * after[0];
  const dot = before[0] * after[0] + before[1] * after[1];
  return Math.abs(Math.atan2(Math.abs(cross), dot)) * 180 / Math.PI;
}

function placementAngle(coordinates, lengths, at, total, lookahead) {
  const direction = directionBetween(
    coordinates,
    lengths,
    Math.max(at - lookahead, 0),
    Math.min(at + lookahead, total),
  );
  if (!direction) return 0;
  return Math.atan2(direction[1], direction[0]) * 180 / Math.PI;
}

function directionBetween(coordinates, lengths, fromDistance, toDistance) {
  const from = pointAt(coordinates, lengths, fromDistance);
  const to = pointAt(coordinates, lengths, toDistance);
  if (!from || !to) return null;
  return [to[0] - from[0], to[1] - from[1]];
}

function pointAt(coordinates, lengths, distance) {
  if (distance <= 0) return [...coordinates[0]];
  if (distance >= lengths[lengths.length - 1]) return [...coordinates[coordinates.length - 1]];

  let low = 0;
  let high = lengths.length - 1;
  while (low < high) {
    const middle = (low + high) >> 1;
    if (lengths[middle] >= distance) high = middle;
    else low = middle + 1;
  }
  const index = Math.max(low, 1);
  const previous = lengths[index - 1];
  const span = lengths[index] - previous;
  const from = coordinates[index - 1];
  const to = coordinates[index];
  if (!(span > 0)) return [...from];

  const ratio = (distance - previous) / span;
  return [from[0] + (to[0] - from[0]) * ratio, from[1] + (to[1] - from[1]) * ratio];
}

// Geographic anchors for live maps. Each line is a `[longitude, latitude]`
// array; one projection frame (scaled by the mean latitude of every line)
// is shared, so a later pass over an already marked stretch — a lap resumed
// after a recording gap, or a second course on the same road — shares its
// marks through `covered`, while the opposite direction keeps its own. The
// angle is map-space, so panning and rotating never invalidate an anchor;
// only a zoom change does. `properties(index)` adds per-line properties.
export function geographicChevronFeatures(lines, { zoom, covered = new Map(), properties = () => ({}) } = {}) {
  const drawable = (Array.isArray(lines) ? lines : []).filter((line) => Array.isArray(line) && line.length >= 2);
  if (drawable.length === 0 || !Number.isFinite(zoom)) return [];

  let latitudeTotal = 0;
  let count = 0;
  for (const line of drawable) {
    for (const coordinate of line) {
      latitudeTotal += coordinate[1];
      count += 1;
    }
  }
  const cosLatitude = Math.max(0.01, Math.cos(((latitudeTotal / count) * Math.PI) / 180));
  const metresPerPixel = (METRES_PER_PIXEL_AT_ZOOM_ZERO * cosLatitude) / (2 ** zoom);
  // The plane is in scaled degrees: one unit is one degree of latitude.
  // Spacing and clearance are screen pixels converted to that frame so the
  // live map keeps the on-screen rhythm.
  const spacing = (CHEVRON_SPACING * metresPerPixel) / METRES_PER_DEGREE;
  const clearance = (CHEVRON_CLEARANCE * metresPerPixel) / METRES_PER_DEGREE;
  const closure = LOOP_CLOSURE_METRES / METRES_PER_DEGREE;

  const features = [];
  (Array.isArray(lines) ? lines : []).forEach((line, index) => {
    if (!Array.isArray(line) || line.length < 2) return;

    const plane = line.map(([longitude, latitude]) => [ longitude * cosLatitude, -latitude ]);
    chevronPlacements(plane, { spacing, clearance, covered, closure }).forEach((placement) => {
      features.push({
        type: "Feature",
        properties: { angle: placement.angle, side: placement.side, ...properties(index) },
        geometry: { type: "Point", coordinates: [ placement.x / cosLatitude, -placement.y ] },
      });
    });
  });
  return features;
}

// Apply the threshold to the whole route after deduplication, not to each
// recording segment. A zoomed-out route with just one or two marks is clearer
// without arrows; the next zoom refresh naturally restores them.
export function directionFeatureCollection(features) {
  return { type: "FeatureCollection", features: features.length >= MIN_DIRECTION_COUNT ? features : [] };
}

// `image` may be an expression, so one layer can carry several baked colours.
// `inline` centres the mark on the line instead of offsetting it to its side
// (the Découvrir map, DESIGN.md §20.6); pair it with an inline image.
export function directionLayer({ source, id = DIRECTION_LAYER_ID, image = DIRECTION_IMAGE_ID, inline = false }) {
  return {
    id,
    type: "symbol",
    source,
    layout: {
      "icon-image": image,
      "icon-size": 1,
      "icon-rotate": ["get", "angle"],
      "icon-rotation-alignment": "map",
      "icon-offset": inline
        ? ["literal", [0, 0]]
        : ["case", ["==", ["get", "side"], -1], ["literal", [0, -12]], ["literal", [0, 12]]],
      "icon-allow-overlap": true,
      "icon-ignore-placement": true,
      "icon-padding": 0,
    },
    paint: {},
  };
}

// The inline mark: an open head centred on the line, drawn in the surface
// colour over a track-coloured border, so it reads as cut into the line
// rather than laid beside it. No shaft: the line is the shaft.
export const INLINE_CHEVRON_POINTS = Object.freeze([
  Object.freeze({ x: 9.5, y: 7.5 }),
  Object.freeze({ x: 14.5, y: 12 }),
  Object.freeze({ x: 9.5, y: 16.5 }),
]);
const INLINE_BORDER_STROKE = 3.6;
const INLINE_CORE_STROKE = 1.7;

export function chevronImageData({ surface, track, devicePixelRatio = 1, inline = false } = {}) {
  if (typeof document === "undefined") return null;

  const ratio = Math.min(CHEVRON_DPR_LIMIT, Math.max(1, Number(devicePixelRatio) || 1));
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(CHEVRON_SIZE * ratio);
  canvas.height = Math.round(CHEVRON_SIZE * ratio);
  const context = canvas.getContext("2d");
  if (!context) return null;

  context.scale(ratio, ratio);
  context.lineJoin = "round";
  context.lineCap = "round";
  if (inline) {
    strokeHead(context, track, INLINE_BORDER_STROKE);
    strokeHead(context, surface, INLINE_CORE_STROKE);
  } else {
    // Surface halo first, then the coloured shaft and open head. The layer's
    // local offset rotates with the icon, keeping it outside a detected loop.
    strokeChevron(context, surface, CHEVRON_HALO_STROKE);
    strokeChevron(context, track, CHEVRON_CORE_STROKE);
  }

  const image = context.getImageData(0, 0, canvas.width, canvas.height);
  return { width: canvas.width, height: canvas.height, data: image.data, pixelRatio: ratio };
}

function strokeChevron(context, colour, width) {
  context.beginPath();
  context.moveTo(5, 12);
  context.lineTo(19, 12);
  context.moveTo(CHEVRON_POINTS[0].x, CHEVRON_POINTS[0].y);
  for (const point of CHEVRON_POINTS.slice(1)) context.lineTo(point.x, point.y);
  context.strokeStyle = colour;
  context.lineWidth = width;
  context.stroke();
}

function strokeHead(context, colour, width) {
  context.beginPath();
  context.moveTo(INLINE_CHEVRON_POINTS[0].x, INLINE_CHEVRON_POINTS[0].y);
  for (const point of INLINE_CHEVRON_POINTS.slice(1)) context.lineTo(point.x, point.y);
  context.strokeStyle = colour;
  context.lineWidth = width;
  context.stroke();
}

export function ensureDirectionImage(map, { id = DIRECTION_IMAGE_ID, ...options } = {}) {
  if (!map || typeof map.hasImage !== "function" || map.hasImage(id)) return false;

  const image = chevronImageData(options);
  if (!image) return false;
  map.addImage(id, image, { pixelRatio: image.pixelRatio });
  return true;
}
