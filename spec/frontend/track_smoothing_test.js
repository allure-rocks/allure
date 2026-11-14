import assert from "node:assert/strict";
import test from "node:test";

import {
  SMOOTHING_HALF_WINDOW_METRES,
  SMOOTHING_LEVELS,
  smoothCoordinates,
  validSmoothingLevel,
} from "../../app/frontend/lib/track_smoothing.js";

// ~16 m east between samples at 45°N: one zigzag in latitude.
function zigzag(length = 9) {
  return Array.from({ length }, (_, index) => [
    6.4 + index * 0.0002,
    45 + (index % 2 === 1 ? 0.00008 : -0.00008),
  ]);
}

test("preserves the point count and both endpoints", () => {
  const points = zigzag();
  const smoothed = smoothCoordinates(points, { level: "medium" });

  assert.equal(smoothed.length, points.length);
  assert.deepEqual(smoothed[0], points[0]);
  assert.deepEqual(smoothed.at(-1), points.at(-1));
});

test("leaves collinear points on the line", () => {
  const points = Array.from({ length: 6 }, (_, index) => [6.4 + index * 0.001, 45]);
  const smoothed = smoothCoordinates(points, { level: "medium" });

  smoothed.forEach((point, index) => {
    assert.ok(Math.abs(point[0] - points[index][0]) < 1e-9);
    assert.ok(Math.abs(point[1] - points[index][1]) < 1e-9);
  });
});

test("reduces a lateral zigzag without folding the route back", () => {
  const points = zigzag();
  const smoothed = smoothCoordinates(points, { level: "medium" });
  // Endpoints are fixed by contract, so compare the interior samples.
  const interior = (series) => Math.max(...series.slice(1, -1).map((point) => Math.abs(point[1] - 45)));
  const rawExcursion = interior(points);
  const smoothedExcursion = interior(smoothed);

  assert.ok(smoothedExcursion < rawExcursion);
  assert.ok(smoothedExcursion > 0);
  const longitudes = smoothed.map((point) => point[0]);
  assert.deepEqual(longitudes, [...longitudes].sort((a, b) => a - b));
});

test("leaves a coarse track whose samples are farther apart than the window", () => {
  const points = Array.from({ length: 5 }, (_, index) => [
    6.4 + index * 0.002,
    45 + (index % 2 === 1 ? 0.001 : 0),
  ]);

  assert.deepEqual(smoothCoordinates(points, { level: "light" }), points);
});

test("keeps stationary clusters finite and bounded to the sample cap", () => {
  const points = Array.from({ length: 400 }, () => [6.4, 45]);
  points.push([6.4001, 45.0001]);
  const smoothed = smoothCoordinates(points, { level: "strong" });

  assert.equal(smoothed.length, points.length);
  assert.ok(smoothed.flat().every(Number.isFinite));
  assert.ok(Math.abs(smoothed[1][1] - 45) < 1e-9);
});

test("exposes the levels and rejects anything else", () => {
  assert.deepEqual(SMOOTHING_LEVELS, ["light", "medium", "strong"]);
  assert.equal(SMOOTHING_HALF_WINDOW_METRES.medium, 25);
  assert.equal(validSmoothingLevel("medium"), true);
  assert.equal(validSmoothingLevel("huge"), false);
  assert.throws(() => smoothCoordinates(zigzag(), { level: "extreme" }), /level/);
  assert.throws(() => smoothCoordinates([[6.4, NaN]], { level: "medium" }), /coordinate/);
});
