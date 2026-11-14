// Courses drawn on the same road on the Découvrir map (DESIGN.md §20.6). Two
// courses that share a stretch would otherwise read as one line, so each
// group of stacked courses takes nuances of the brand primary — never an
// invented hue, never a sport colour (§6) — while a course alone keeps the
// primary like every other map. Shorter courses draw above longer ones, so
// a climb nested in a longer course stays visible and clickable.
//
// Pure and framework-independent: lines are `[longitude, latitude]` arrays.
const METRES_PER_DEGREE = 111_319.49;

// Two courses share a stretch when one runs within this distance of the
// other (a 3 × 3 neighbourhood of cells this wide).
export const OVERLAP_TOLERANCE_METRES = 25;
// …for at least this long, or half of the shorter one. A crossing shares a
// few samples only, so crossing roads never count as stacked.
export const OVERLAP_MIN_SHARED_METRES = 200;

export const SHADE_COUNT = 4;

// `{ shade, sortKey, length }` per line, in input order. `shade` indexes the
// palette below (0 is the primary); `sortKey` is higher for shorter courses,
// for MapLibre's `line-sort-key`, which draws higher keys on top.
export function courseLayout(lines, { tolerance = OVERLAP_TOLERANCE_METRES, minShared = OVERLAP_MIN_SHARED_METRES } = {}) {
  const list = Array.isArray(lines) ? lines : [];
  const cosLatitude = frameCosine(list);
  const tracks = list.map((line) => resample(planar(line, cosLatitude), tolerance));

  const grid = new Map();
  tracks.forEach((track, index) => {
    for (const [x, y] of track.samples) {
      const key = cellKey(Math.floor(x / tolerance), Math.floor(y / tolerance));
      if (!grid.has(key)) grid.set(key, new Set());
      grid.get(key).add(index);
    }
  });

  const neighbours = list.map(() => new Set());
  tracks.forEach((track, index) => {
    const shared = new Map();
    for (const [x, y] of track.samples) {
      const cellX = Math.floor(x / tolerance);
      const cellY = Math.floor(y / tolerance);
      const near = new Set();
      for (let dx = -1; dx <= 1; dx += 1) {
        for (let dy = -1; dy <= 1; dy += 1) {
          for (const other of grid.get(cellKey(cellX + dx, cellY + dy)) || []) {
            if (other !== index) near.add(other);
          }
        }
      }
      near.forEach((other) => shared.set(other, (shared.get(other) || 0) + 1));
    }

    shared.forEach((count, other) => {
      const sharedLength = count * tolerance;
      const shorter = Math.min(track.length, tracks[other].length);
      if (sharedLength >= Math.min(minShared, shorter / 2)) {
        neighbours[index].add(other);
        neighbours[other].add(index);
      }
    });
  });

  const order = list
    .map((_, index) => index)
    .sort((a, b) => tracks[b].length - tracks[a].length || a - b);

  const shades = new Array(list.length).fill(0);
  const assigned = new Set();
  order.forEach((index) => {
    const used = new Set();
    neighbours[index].forEach((other) => {
      if (assigned.has(other)) used.add(shades[other]);
    });
    let shade = 0;
    while (used.has(shade) && shade < SHADE_COUNT) shade += 1;
    shades[index] = shade % SHADE_COUNT;
    assigned.add(index);
  });

  const rank = new Array(list.length).fill(0);
  order.forEach((index, position) => { rank[index] = position; });

  return list.map((_, index) => ({ shade: shades[index], sortKey: rank[index], length: tracks[index].length }));
}

// Nuances of the primary, contrasted with the basemap first: darker steps on
// the light basemap, lighter ones on the dark basemap, and only the last one
// on the other side, where it reads least.
export function courseShadePalette(primary, basemapTheme) {
  const base = parseColour(primary);
  if (!base) return new Array(SHADE_COUNT).fill(primary);

  const black = [ 0, 0, 0 ];
  const white = [ 255, 255, 255 ];
  const steps = basemapTheme === "dark"
    ? [ [ white, 0.38 ], [ white, 0.66 ], [ black, 0.28 ] ]
    : [ [ black, 0.3 ], [ black, 0.55 ], [ white, 0.4 ] ];
  return [ toHex(base), ...steps.map(([ target, amount ]) => toHex(mix(base, target, amount))) ];
}

function frameCosine(lines) {
  let total = 0;
  let count = 0;
  for (const line of lines) {
    if (!Array.isArray(line)) continue;
    for (const coordinate of line) {
      total += coordinate[1];
      count += 1;
    }
  }
  const latitude = count > 0 ? total / count : 0;
  return Math.max(0.01, Math.cos((latitude * Math.PI) / 180));
}

function planar(line, cosLatitude) {
  if (!Array.isArray(line)) return [];
  return line
    .filter((point) => Array.isArray(point) && Number.isFinite(point[0]) && Number.isFinite(point[1]))
    .map(([ longitude, latitude ]) => [ longitude * cosLatitude * METRES_PER_DEGREE, latitude * METRES_PER_DEGREE ]);
}

// One sample every `step` metres along the line, both ends included.
function resample(points, step) {
  if (points.length === 0) return { samples: [], length: 0 };

  const samples = [ points[0] ];
  let length = 0;
  let carried = 0;
  for (let index = 1; index < points.length; index += 1) {
    const [ fromX, fromY ] = points[index - 1];
    const [ toX, toY ] = points[index];
    const span = Math.hypot(toX - fromX, toY - fromY);
    if (!(span > 0)) continue;

    let at = step - carried;
    while (at <= span) {
      const ratio = at / span;
      samples.push([ fromX + (toX - fromX) * ratio, fromY + (toY - fromY) * ratio ]);
      at += step;
    }
    carried = span - (at - step);
    length += span;
  }
  samples.push(points[points.length - 1]);
  return { samples, length };
}

function cellKey(x, y) {
  return `${x},${y}`;
}

// "#rrggbb" or an "rgb(r, g, b)" computed value.
function parseColour(value) {
  const text = String(value || "").trim();
  const hex = /^#([0-9a-f]{6})$/i.exec(text);
  if (hex) {
    const number = parseInt(hex[1], 16);
    return [ (number >> 16) & 255, (number >> 8) & 255, number & 255 ];
  }
  const rgb = /rgba?\(([^)]+)\)/.exec(text);
  if (rgb) {
    const channels = rgb[1].split(",").slice(0, 3).map((part) => parseFloat(part));
    if (channels.length === 3 && channels.every(Number.isFinite)) return channels;
  }
  return null;
}

function mix(from, to, amount) {
  return from.map((channel, index) => Math.round(channel + (to[index] - channel) * amount));
}

function toHex(channels) {
  return `#${channels.map((channel) => Math.max(0, Math.min(255, Math.round(channel))).toString(16).padStart(2, "0")).join("")}`;
}
