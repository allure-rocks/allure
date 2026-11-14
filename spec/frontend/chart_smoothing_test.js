import assert from "node:assert/strict";
import test from "node:test";

import {
  CHART_SMOOTHING_LEVEL,
  bridgeShortGaps,
  chartHalfWindowMetres,
  smoothSeriesValues,
} from "../../app/frontend/lib/chart_smoothing.js";

test("preserves the sample count and every gap", () => {
  const values = [10, 12, null, 30, 32, 34];
  const distances = [0, 5, 10, 15, 20, 25];
  const smoothed = smoothSeriesValues(values, distances);

  assert.equal(smoothed.length, values.length);
  assert.equal(smoothed[2], null);
});

test("fixes the run endpoints and pulls a spike towards its neighbours", () => {
  const values = [20, 20, 20, 20, 20, 100, 20, 20, 20, 20, 20];
  const distances = values.map((_, index) => index * 5);
  const smoothed = smoothSeriesValues(values, distances);

  assert.equal(smoothed[0], 20);
  assert.equal(smoothed.at(-1), 20);
  assert.ok(smoothed[5] < 60, `expected the spike to be reduced, got ${smoothed[5]}`);
  assert.ok(smoothed[5] > 20);
  assert.ok(smoothed[4] > 20, "the neighbours absorb part of the spike");
});

test("leaves a series coarser than the window untouched", () => {
  const values = [10, 60, 20, 80, 30];
  const distances = values.map((_, index) => index * 50);
  const smoothed = smoothSeriesValues(values, distances);

  assert.deepEqual(smoothed, values);
});

test("does not bridge a recording gap", () => {
  const values = [10, null, 30, 40, 50];
  const distances = [0, 5, 10, 15, 20];
  const smoothed = smoothSeriesValues(values, distances);

  assert.equal(smoothed[1], null);
  assert.equal(smoothed[2], 30);
  assert.equal(smoothed[4], 50);
});

test("runs at the documented medium level", () => {
  assert.equal(CHART_SMOOTHING_LEVEL, "medium");
});

test("rejects an unknown level and mismatched inputs", () => {
  assert.throws(() => smoothSeriesValues([1, 2], [0, 1], { level: "hard" }));
  assert.throws(() => smoothSeriesValues([1, 2], [0]));
  assert.throws(() => smoothSeriesValues("nope", [0]));
});

test("widens the window with the plotted span, never below the medium level", () => {
  assert.equal(chartHalfWindowMetres(1_000), 25);
  assert.equal(chartHalfWindowMetres(10_000), 100);
  assert.equal(chartHalfWindowMetres(10_000, { compact: true }), 10_000 / 60);
  assert.equal(chartHalfWindowMetres(Number.NaN), 25);
});

test("an explicit half window flattens noise the medium window keeps", () => {
  const values = Array.from({ length: 41 }, (_, index) => (index % 2 === 0 ? 10 : 14));
  const distances = values.map((_, index) => index * 10);
  const medium = smoothSeriesValues(values, distances);
  const wide = smoothSeriesValues(values, distances, { halfWindowMetres: 100 });
  const spread = (series) => Math.max(...series.slice(5, -5)) - Math.min(...series.slice(5, -5));

  assert.ok(spread(wide) < spread(medium), `expected ${spread(wide)} < ${spread(medium)}`);
  assert.throws(() => smoothSeriesValues(values, distances, { halfWindowMetres: 0 }));
});

test("bridges a short sensor hole for display, never a long one or a recording gap", () => {
  const values = [100, null, 110, null, null, null, null, 150, 160];
  const distances = [0, 10, 20, 30, 40, 50, 300, 310, 320];
  const segments = [0, 0, 0, 0, 0, 0, 0, 1, 1];

  const bridged = bridgeShortGaps(values, distances, { maxGapMetres: 50 });
  assert.equal(bridged[1], 105);
  assert.deepEqual(bridged.slice(3, 7), [null, null, null, null]);
  assert.equal(values[1], null, "the input is left untouched");

  const acrossSegments = bridgeShortGaps([1, null, 3], [0, 5, 10], { maxGapMetres: 50, segments: [0, 0, 1] });
  assert.equal(acrossSegments[1], null);
});
