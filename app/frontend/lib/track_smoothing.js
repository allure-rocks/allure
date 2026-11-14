// Display-time smoothing of an already-unwrapped polyline, mirroring
// `Allure::Geometry::Smoothing` so the live map and the server-rendered route
// images draw the same line. See that module for why the transform preserves
// the point count: the per-point metric arrays and the map's hover, selection
// and colour ramp are all index-aligned with the coordinates.
export const SMOOTHING_HALF_WINDOW_METRES = Object.freeze({
  light: 10,
  medium: 25,
  strong: 40,
});

export const SMOOTHING_LEVELS = Object.freeze(Object.keys(SMOOTHING_HALF_WINDOW_METRES));

// Bounds the filter cost on a stationary recording, exactly as the Ruby
// implementation does. The window stays symmetric so near-duplicate samples do
// not bias the result in one direction.
const MAX_WINDOW_SAMPLES = 61;
const MAX_WINDOW_SIDE = (MAX_WINDOW_SAMPLES - 1) / 2;
const EARTH_RADIUS_METRES = 6_378_137.0;

export function validSmoothingLevel(level) {
  return SMOOTHING_LEVELS.includes(String(level));
}

export function smoothCoordinates(coordinates, { level = "medium" } = {}) {
  if (!validSmoothingLevel(level)) throw new Error("unknown smoothing level");

  const points = normalizeCoordinates(coordinates);
  if (points.length < 3) return points.map((point) => [point[0], point[1]]);

  const halfWindow = SMOOTHING_HALF_WINDOW_METRES[String(level)];
  const lengths = cumulativeLengths(points);
  if (!(lengths[lengths.length - 1] > 0)) return points.map((point) => [point[0], point[1]]);

  return points.map((point, index) => {
    if (index === 0 || index === points.length - 1) return [point[0], point[1]];
    return windowMean(points, lengths, index, halfWindow) ?? [point[0], point[1]];
  });
}

function normalizeCoordinates(coordinates) {
  if (!Array.isArray(coordinates)) throw new Error("invalid coordinate");

  return coordinates.map((coordinate) => {
    if (!Array.isArray(coordinate) || coordinate.length < 2) throw new Error("invalid coordinate");

    const longitude = Number(coordinate[0]);
    const latitude = Number(coordinate[1]);
    if (!Number.isFinite(longitude) || !Number.isFinite(latitude)) throw new Error("invalid coordinate");

    return [longitude, latitude];
  });
}

function cumulativeLengths(points) {
  const lengths = [0];
  for (let index = 1; index < points.length; index += 1) {
    lengths.push(lengths[index - 1] + distanceMetres(points[index - 1], points[index]));
  }
  return lengths;
}

function windowMean(points, lengths, index, halfWindow) {
  const left = Math.max(index - MAX_WINDOW_SIDE, 0);
  const right = Math.min(index + MAX_WINDOW_SIDE, points.length - 1);
  let total = 0;
  let longitude = 0;
  let latitude = 0;

  for (let position = left; position <= right; position += 1) {
    const span = Math.abs(lengths[position] - lengths[index]);
    if (span > halfWindow) continue;

    const weight = 1 - span / halfWindow;
    total += weight;
    longitude += points[position][0] * weight;
    latitude += points[position][1] * weight;
  }

  return total > 0 ? [longitude / total, latitude / total] : null;
}

// Short equirectangular distance, the same short-delta form as
// `Allure::Gpx::Geo.horizontal_distance`. A window spans a few metres, so a
// full haversine would only add cost.
function distanceMetres([longitudeA, latitudeA], [longitudeB, latitudeB]) {
  const deltaLatitude = toRadians(latitudeB - latitudeA);
  const deltaLongitude = toRadians(normalizedLongitudeDelta(longitudeB - longitudeA));
  const x = deltaLongitude * Math.cos(toRadians(latitudeA));
  const y = deltaLatitude;
  return Math.sqrt((x * x) + (y * y)) * EARTH_RADIUS_METRES;
}

function normalizedLongitudeDelta(delta) {
  let normalized = delta % 360;
  if (normalized > 180) normalized -= 360;
  return normalized;
}

function toRadians(degrees) {
  return (degrees * Math.PI) / 180;
}
