// Display-time smoothing of a numeric chart series. It mirrors the distance
// window of `track_smoothing.js` (and, through it, `Allure::Geometry::Smoothing`)
// so the speed or heart-rate trend reads at the same scale as a smoothed map.
//
// The transform is deliberately display-only and **point-count preserving**:
// the chart's tooltip, its "Voir les données" table and the map hover all read
// the recorded sample at the same index, so a point moving or disappearing
// would silently change what they mean. Missing readings stay missing — they
// are never interpolated into a value the file did not record (DESIGN.md §15.1).
import { SMOOTHING_HALF_WINDOW_METRES, validSmoothingLevel } from "./track_smoothing.js";

// Bounds the filter cost on a stationary recording, exactly as the track
// smoothing does. The window stays symmetric so near-duplicate samples do not
// bias the result in one direction.
const MAX_WINDOW_SAMPLES = 61;
const MAX_WINDOW_SIDE = (MAX_WINDOW_SAMPLES - 1) / 2;

// The metric lines are physiological and speed readings: the map's medium
// window (25 m) is the right scale for both and needs no account preference.
export const CHART_SMOOTHING_LEVEL = "medium";

// The profile's secondary line reads at the scale of the drawn profile, not of
// the map: a fixed 25 m window leaves a running pace as noisy as the raw
// samples once a whole 10 km lies across a few hundred pixels. The window
// therefore grows with the plotted span, never below the medium level.
export const CHART_SPAN_WINDOW_DIVISOR = 100;
export const CHART_SPAN_WINDOW_DIVISOR_COMPACT = 60;

export function chartHalfWindowMetres(spanMetres, { compact = false } = {}) {
  const floor = SMOOTHING_HALF_WINDOW_METRES[CHART_SMOOTHING_LEVEL];
  if (!Number.isFinite(spanMetres) || spanMetres <= 0) return floor;

  const divisor = compact ? CHART_SPAN_WINDOW_DIVISOR_COMPACT : CHART_SPAN_WINDOW_DIVISOR;
  return Math.max(floor, spanMetres / divisor);
}

// A sensor that reports every few samples (a heart-rate strap, a cadence pod)
// leaves the series full of one- or two-sample holes, which would draw as
// dust. For display only, a hole no longer than `maxGapMetres` between two
// readings of the same recording segment is filled by linear interpolation;
// a longer hole, and any hole across a recording gap, stays a gap. The input
// is not modified, and the tooltip keeps reading the recorded samples.
export function bridgeShortGaps(values, distances, { maxGapMetres, segments = null } = {}) {
  if (!Array.isArray(values) || !Array.isArray(distances) || values.length !== distances.length) {
    throw new Error("values and distances must be arrays of the same length");
  }
  if (!(Number.isFinite(maxGapMetres) && maxGapMetres > 0)) return values.slice();

  const bridged = values.map((value) => (Number.isFinite(value) ? value : null));
  let previous = -1;
  for (let index = 0; index < bridged.length; index += 1) {
    if (bridged[index] === null) continue;

    if (previous >= 0 && index - previous > 1) {
      const span = distances[index] - distances[previous];
      const sameSegment = !segments || segments[index] === segments[previous];
      if (sameSegment && Number.isFinite(span) && span >= 0 && span <= maxGapMetres) {
        for (let hole = previous + 1; hole < index; hole += 1) {
          const ratio = span > 0 ? (distances[hole] - distances[previous]) / span : (hole - previous) / (index - previous);
          bridged[hole] = bridged[previous] + (bridged[index] - bridged[previous]) * ratio;
        }
      }
    }
    previous = index;
  }
  return bridged;
}

export function smoothSeriesValues(values, distances, { level = CHART_SMOOTHING_LEVEL, halfWindowMetres = null } = {}) {
  if (!validSmoothingLevel(level)) throw new Error("unknown smoothing level");
  if (!Array.isArray(values) || !Array.isArray(distances) || values.length !== distances.length) {
    throw new Error("values and distances must be arrays of the same length");
  }
  if (halfWindowMetres !== null && !(Number.isFinite(halfWindowMetres) && halfWindowMetres > 0)) {
    throw new Error("halfWindowMetres must be a positive number");
  }

  const smoothed = values.map((value) => (Number.isFinite(value) ? value : null));
  const halfWindow = halfWindowMetres ?? SMOOTHING_HALF_WINDOW_METRES[String(level)];

  let index = 0;
  while (index < smoothed.length) {
    if (smoothed[index] === null) {
      index += 1;
      continue;
    }

    const start = index;
    while (index + 1 < smoothed.length && smoothed[index + 1] !== null) index += 1;
    smoothRun(smoothed, distances, start, index, halfWindow);
    index += 1;
  }

  return smoothed;
}

// A run is a maximal sequence of recorded readings; a gap is never bridged.
// The run's endpoints are fixed, like the polyline endpoints of the track
// smoothing, so the first and last readings the file recorded are shown as is.
function smoothRun(output, distances, start, end, halfWindow) {
  if (end - start < 2) return;

  const readings = output.slice(start, end + 1);
  for (let position = 1; position < readings.length - 1; position += 1) {
    const left = Math.max(position - MAX_WINDOW_SIDE, 0);
    const right = Math.min(position + MAX_WINDOW_SIDE, readings.length - 1);
    let total = 0;
    let sum = 0;

    for (let offset = left; offset <= right; offset += 1) {
      const span = Math.abs(distances[start + offset] - distances[start + position]);
      if (!Number.isFinite(span) || span > halfWindow) continue;

      const weight = 1 - span / halfWindow;
      total += weight;
      sum += readings[offset] * weight;
    }

    // A coarse series whose samples are farther apart than the window keeps
    // its recorded reading rather than being flattened to nothing.
    if (total > 0) output[start + position] = sum / total;
  }
}
