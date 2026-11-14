import assert from "node:assert/strict";
import test from "node:test";

import { SHADE_COUNT, courseLayout, courseShadePalette } from "../../app/frontend/lib/course_overlaps.js";

// About 111 m per 0.001° of latitude; longitude scaled near 45° N.
const north = (longitude, fromLatitude, toLatitude, steps = 20) =>
  Array.from({ length: steps + 1 }, (_, index) => [ longitude, fromLatitude + ((toLatitude - fromLatitude) * index) / steps ]);

test("keeps the primary for courses that never share a road", () => {
  const layout = courseLayout([ north(6.0, 45.0, 45.02), north(6.1, 45.0, 45.02) ]);

  assert.deepEqual(layout.map((entry) => entry.shade), [ 0, 0 ]);
});

test("gives stacked courses distinct nuances, the longest keeping the primary", () => {
  const long = north(6.0, 45.0, 45.03);
  const nested = north(6.0, 45.01, 45.02);
  const reversed = north(6.0001, 45.025, 45.005);

  const layout = courseLayout([ nested, long, reversed ]);

  assert.equal(layout[1].shade, 0);
  assert.notEqual(layout[0].shade, layout[1].shade);
  assert.notEqual(layout[2].shade, layout[1].shade);
  assert.notEqual(layout[0].shade, layout[2].shade);
});

test("draws shorter courses above longer ones", () => {
  const layout = courseLayout([ north(6.0, 45.0, 45.03), north(6.0, 45.01, 45.02) ]);

  assert.ok(layout[1].sortKey > layout[0].sortKey);
  assert.ok(layout[0].length > layout[1].length);
});

test("does not count a crossing as a shared stretch", () => {
  const southNorth = north(6.0, 44.99, 45.01);
  const westEast = Array.from({ length: 21 }, (_, index) => [ 5.987 + (0.026 * index) / 20, 45.0 ]);

  assert.deepEqual(courseLayout([ southNorth, westEast ]).map((entry) => entry.shade), [ 0, 0 ]);
});

test("treats a short course lying on a longer one as stacked", () => {
  // About 150 m, under the 200 m floor, but entirely on the longer course.
  const layout = courseLayout([ north(6.0, 45.0, 45.03), north(6.0, 45.01, 45.01135, 4) ]);

  assert.notEqual(layout[1].shade, layout[0].shade);
});

test("builds one palette per basemap, primary first, most contrasted next", () => {
  const light = courseShadePalette("#c5426c", "light");
  const dark = courseShadePalette("rgb(197, 66, 108)", "dark");

  assert.equal(light.length, SHADE_COUNT);
  assert.equal(light[0], "#c5426c");
  assert.equal(dark[0], "#c5426c");
  // Darker than the primary on the light basemap, lighter on the dark one,
  // for the first two steps.
  for (const shade of [ 1, 2 ]) {
    assert.ok(parseInt(light[shade].slice(1, 3), 16) < 0xc5);
    assert.ok(parseInt(dark[shade].slice(1, 3), 16) > 0xc5);
  }
  assert.equal(new Set(light).size, SHADE_COUNT);
});

test("ignores malformed lines", () => {
  assert.deepEqual(courseLayout([ null, [], [ [ "x", 1 ] ] ]).map((entry) => entry.shade), [ 0, 0, 0 ]);
});
