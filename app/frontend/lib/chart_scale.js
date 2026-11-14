// Axis scales a reader can count on: every tick is a round value (50, 100,
// 150 — never 117 or 183) and the axis spans only what the readings use.
//
// `niceScale` picks the smallest step from `steps` (or the 1-2-5 decades) that
// fits the range in at most `maxTicks` intervals, then snaps both ends to it.
// The returned `step` is the axis `interval` and `ticks` the interval count,
// so each label lands exactly on a multiple of the step.

// Pace axes are durations in seconds: steps follow the clock, not decimals.
export const PACE_STEPS = Object.freeze([5, 10, 15, 20, 30, 60, 120, 180, 300, 600, 900, 1800]);

export function niceScale(minimum, maximum, maxTicks = 5, steps = null) {
  if (!Number.isFinite(minimum) || !Number.isFinite(maximum)) return { min: 0, max: 1, ticks: 1 };

  const low = Math.min(minimum, maximum);
  const high = Math.max(minimum, maximum);
  const intervals = Math.max(1, Math.floor(maxTicks));
  const range = high - low;
  const step = pickStep(range > 0 ? range : Math.abs(high) || 1, intervals, steps);

  let min = Math.floor(low / step) * step;
  let max = Math.ceil(high / step) * step;
  if (max === min) max = min + step;
  // Snapping both ends can add an interval; widen the step until it fits.
  if (Math.round((max - min) / step) > intervals) {
    return niceScale(low, high, maxTicks, steps ? steps.filter((candidate) => candidate > step) : [step * 2, step * 5, step * 10]);
  }
  min = roundTo(min, step);
  max = roundTo(max, step);

  return { min, max, ticks: Math.max(1, Math.round((max - min) / step)), step };
}

// The bulk of the readings: the 2nd to the 98th percentile, so a single stop
// or sensor spike does not decide the axis.
export function robustExtent(values, lower = 0.02, upper = 0.98) {
  const sorted = values.filter(Number.isFinite).sort((a, b) => a - b);
  if (sorted.length === 0) return [0, 1];

  const at = (fraction) => sorted[Math.min(sorted.length - 1, Math.max(0, Math.round(fraction * (sorted.length - 1))))];
  return [at(lower), at(upper)];
}

function pickStep(range, intervals, steps) {
  const raw = range / intervals;
  if (steps?.length) return steps.find((candidate) => candidate >= raw) ?? steps.at(-1) * Math.ceil(raw / steps.at(-1));

  const magnitude = 10 ** Math.floor(Math.log10(raw));
  for (const factor of [1, 2, 5, 10]) {
    if (factor * magnitude >= raw) return factor * magnitude;
  }
  return 10 * magnitude;
}

// Removes floating-point dust (0.30000000000000004) from snapped ends.
function roundTo(value, step) {
  const decimals = Math.max(0, -Math.floor(Math.log10(step)) + 1);
  return Number(value.toFixed(decimals));
}
