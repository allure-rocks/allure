import assert from "node:assert/strict";
import test from "node:test";

import { PACE_STEPS, niceScale, robustExtent } from "../../app/frontend/lib/chart_scale.js";

const ticksOf = ({ min, max, ticks }) => Array.from({ length: ticks + 1 }, (_, index) => min + ((max - min) / ticks) * index);

test("elevation ticks land on round values", () => {
  const scale = niceScale(79, 235, 4);

  assert.deepEqual(ticksOf(scale), [50, 100, 150, 200, 250]);
});

test("never more intervals than asked", () => {
  const scale = niceScale(79, 235, 3);

  assert.ok(scale.ticks <= 3, JSON.stringify(scale));
});

test("five ticks on a wider chart", () => {
  const scale = niceScale(79, 235, 5);

  assert.deepEqual([scale.min, scale.max], [50, 250]);
  assert.equal(scale.ticks, 4);
  assert.ok(ticksOf(scale).every((value) => value % 50 === 0));
});

test("pace ticks follow the clock", () => {
  // 5:05 to 6:50 per km, in seconds.
  const scale = niceScale(305, 410, 5, PACE_STEPS);

  assert.ok(ticksOf(scale).every((value) => value % 30 === 0), JSON.stringify(scale));
  assert.ok(scale.min <= 305 && scale.max >= 410);
  assert.ok(scale.min > 0, "a pace axis never starts at 0:00");
});

test("a flat series still gets an interval", () => {
  const scale = niceScale(120, 120, 5);

  assert.ok(scale.max > scale.min);
});

test("decimals do not leak floating-point dust", () => {
  const scale = niceScale(0.1, 0.7, 3);

  assert.equal(String(scale.min).length <= 4, true, String(scale.min));
  assert.equal(String(scale.max).length <= 4, true, String(scale.max));
});

test("the robust extent ignores a lone spike", () => {
  const values = [...Array.from({ length: 200 }, (_, index) => 300 + (index % 20)), 1800];

  assert.deepEqual(robustExtent(values), [300, 319]);
});
