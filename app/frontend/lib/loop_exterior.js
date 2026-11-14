// Display-only topology, in an already projected plane whose y grows down.
// Erase each closed excursion from the working path: a figure eight then has
// two independent windings, rather than one misleading total signed area.
// No connection is inferred between separate recording segments.
export const LOOP_CLOSURE_METRES = 30;
const MAX_SAMPLES = 20_000;
const MAX_CELL_VISITS = 32;

export function loopExteriorSides(points, distances, { closure = 10 } = {}) {
  const sides = distances.map(() => 1);
  if (points.length < 3 || !(closure > 0) || distances.length === 0) return sides;
  const [originX, originY] = points[0];
  points = points.map(([x, y]) => [x - originX, y - originY]);

  const lengths = [0];
  for (let index = 1; index < points.length; index += 1) {
    lengths.push(lengths[index - 1] + Math.hypot(
      points[index][0] - points[index - 1][0], points[index][1] - points[index - 1][1],
    ));
  }
  const total = lengths.at(-1);
  if (total < 8 * closure) return sides;

  const stack = [];
  const grid = new Map();
  const ranges = [];
  const count = Math.min(MAX_SAMPLES, Math.ceil(total / (closure / 2)));
  let edge = 1;

  for (let index = 0; index <= count; index += 1) {
    const at = total * index / count;
    while (edge < points.length - 1 && lengths[edge] < at) edge += 1;
    const span = lengths[edge] - lengths[edge - 1];
    const ratio = span > 0 ? (at - lengths[edge - 1]) / span : 0;
    const x = points[edge - 1][0] + ratio * (points[edge][0] - points[edge - 1][0]);
    const y = points[edge - 1][1] + ratio * (points[edge][1] - points[edge - 1][1]);
    const previous = stack.at(-1);
    const area = previous ? previous.area + cross(previous.x, previous.y, x, y) : 0;
    const cellX = Math.floor(x / closure);
    const cellY = Math.floor(y / closure);
    let match = null;
    let nearest = Infinity;

    for (let dx = -1; dx <= 1; dx += 1) {
      for (let dy = -1; dy <= 1; dy += 1) {
        for (const candidate of grid.get(`${cellX + dx},${cellY + dy}`) || []) {
          const perimeter = at - candidate.at;
          if (perimeter < 8 * closure) continue;
          const gap = Math.hypot(x - candidate.x, y - candidate.y);
          if (gap > closure || gap >= nearest) continue;
          const winding = area - candidate.area + cross(x, y, candidate.x, candidate.y);
          // Reject retracing, GPS wobble and near-zero-area excursions.
          if (Math.abs(winding) <= 2 * closure * perimeter) continue;
          match = { candidate, winding };
          nearest = gap;
        }
      }
    }

    if (match) {
      const { candidate, winding } = match;
      ranges.push({ start: candidate.at - closure, end: at + closure, side: winding > 0 ? -1 : 1 });
      while (stack.length > candidate.index) {
        const removed = stack.pop();
        const bucket = grid.get(removed.key);
        const position = bucket?.indexOf(removed) ?? -1;
        if (position !== -1) bucket.splice(position, 1);
        if (bucket?.length === 0) grid.delete(removed.key);
      }
    }

    const tail = stack.at(-1);
    const key = `${cellX},${cellY}`;
    const node = { x, y, at, key, index: stack.length, area: tail ? tail.area + cross(tail.x, tail.y, x, y) : 0 };
    stack.push(node);
    if (!grid.has(key)) grid.set(key, []);
    const bucket = grid.get(key);
    // Preserve early visits as well as recent ones, with bounded work even
    // when a stationary recording jitters repeatedly in one small cell.
    if (bucket.length === MAX_CELL_VISITS) bucket.splice(MAX_CELL_VISITS / 2, 1);
    bucket.push(node);
  }

  // Earlier (inner) loops win over later enclosing excursions. A successor
  // index assigns each requested arrow once, avoiding loops × arrows scans.
  const next = Array.from({ length: distances.length + 1 }, (_, index) => index);
  const unassigned = (index) => {
    let root = index;
    while (next[root] !== root) root = next[root];
    while (next[index] !== index) {
      const following = next[index];
      next[index] = root;
      index = following;
    }
    return root;
  };
  for (const range of ranges) {
    let low = 0;
    let high = distances.length;
    while (low < high) {
      const middle = (low + high) >> 1;
      if (distances[middle] < range.start) low = middle + 1;
      else high = middle;
    }
    for (let index = unassigned(low); index < distances.length && distances[index] <= range.end; index = unassigned(index)) {
      sides[index] = range.side;
      next[index] = unassigned(index + 1);
    }
  }
  return sides;
}

function cross(x1, y1, x2, y2) {
  return x1 * y2 - y1 * x2;
}
