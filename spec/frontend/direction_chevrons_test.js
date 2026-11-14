import assert from "node:assert/strict";
import test from "node:test";
import { loopExteriorSides } from "../../app/frontend/lib/loop_exterior.js";

import {
  CHEVRON_CLEARANCE,
  CHEVRON_POINTS,
  CHEVRON_SPACING,
  DIRECTION_IMAGE_ID,
  DIRECTION_LAYER_ID,
  INLINE_CHEVRON_POINTS,
  chevronPlacements,
  directionFeatureCollection,
  directionLayer,
  ensureDirectionImage,
  geographicChevronFeatures,
} from "../../app/frontend/lib/direction_chevrons.js";

test("places direction points at a fixed spacing on the line source", () => {
  assert.deepEqual(directionLayer({ source: "allure-track" }), {
    id: DIRECTION_LAYER_ID,
    type: "symbol",
    source: "allure-track",
    layout: {
      "icon-image": DIRECTION_IMAGE_ID,
      "icon-size": 1,
      "icon-rotate": ["get", "angle"],
      "icon-rotation-alignment": "map",
      "icon-offset": ["case", ["==", ["get", "side"], -1], ["literal", [0, -12]], ["literal", [0, 12]]],
      "icon-allow-overlap": true,
      "icon-ignore-placement": true,
      "icon-padding": 0,
    },
    paint: {},
  });
  assert.equal(CHEVRON_SPACING, 320);
});

test("hides fewer than three deduplicated arrows across the whole route", () => {
  const features = [0, 1, 2].map((segment_index) => ({
    type: "Feature", properties: { segment_index, angle: 0, side: 1 }, geometry: { type: "Point", coordinates: [segment_index, 0] },
  }));
  for (const count of [0, 1, 2]) {
    assert.deepEqual(directionFeatureCollection(features.slice(0, count)), { type: "FeatureCollection", features: [] });
  }
  // One arrow in each recording segment still meets the global threshold.
  assert.deepEqual(directionFeatureCollection(features), { type: "FeatureCollection", features });
});

test("keeps the regular spacing on a straight run", () => {
  const placements = chevronPlacements([[0, 0], [1000, 0]], { spacing: 240, clearance: CHEVRON_CLEARANCE });

  assert.deepEqual(placements.map((placement) => placement.x), [120, 360, 600, 840]);
  assert.deepEqual(placements.map((placement) => placement.y), [0, 0, 0, 0]);
  assert.deepEqual(placements.map((placement) => placement.angle), [0, 0, 0, 0]);
});

test("moves a chevron off a corner instead of placing it on the turn", () => {
  const placements = chevronPlacements([[0, 0], [400, 0], [400, 900]], { spacing: 240, clearance: 0 });

  assert.deepEqual(placements.map((placement) => placement.x), [120, 320, 400, 400, 400]);
  assert.deepEqual(placements.map((placement) => placement.angle), [0, 0, 90, 90, 90]);
  assert.deepEqual([placements[1].x, placements[1].y], [320, 0]);
});

test("keeps the regular spacing on a jittery straight run", () => {
  const points = Array.from({ length: 200 }, (_, index) => [index * 5, index % 2 === 1 ? 0.6 : -0.6]);

  const placements = chevronPlacements(points, { spacing: 240, clearance: 24 });

  // The jitter lengthens the path, so the slot centres land at these x
  // positions; without the straightness tolerance they would wander through
  // the slot instead.
  assert.deepEqual(placements.map((placement) => Number(placement.x.toFixed(2))), [116.69, 350.06, 583.43, 816.81]);
  placements.forEach((placement) => assert.ok(Math.abs(placement.angle) <= 0.5));
});

test("still places one chevron on a trace shorter than the first slot", () => {
  const placements = chevronPlacements([[0, 0], [100, 0]], { clearance: 10 });

  assert.deepEqual(placements, [{ x: 50, y: 0, angle: 0, side: 1 }]);
});

test("draws nothing without two points or any length", () => {
  assert.deepEqual(chevronPlacements([[0, 0]]), []);
  assert.deepEqual(chevronPlacements([[0, 0], [0, 0]]), []);
  assert.deepEqual(chevronPlacements([[0, 0], [40, 0]]), []);
});

test("does not accumulate arrows on repeated laps, even with shifted slots", () => {
  const loop = [[0, 0], [400, 0], [400, 400], [0, 400], [0, 0]];
  const once = chevronPlacements(loop);
  const repeated = chevronPlacements([...loop, ...loop.slice(1), ...loop.slice(1)]);
  assert.equal(repeated.length, once.length);
  assert.deepEqual(repeated.slice(0, -1), once.slice(0, -1));
  // The closing corner is now internal, so its tangent window is no longer
  // clipped at the recording endpoint; it may choose a different anchor.
  assert.equal(repeated.at(-1).angle, -90);
});

test("shares coverage across recording gaps and preserves the return direction", () => {
  const covered = new Map();
  const outward = [[0, 0], [1000, 0]];
  assert.equal(chevronPlacements(outward, { covered }).length, 3);
  assert.deepEqual(chevronPlacements(outward, { covered }), []);
  assert.equal(chevronPlacements([...outward].reverse(), { covered }).length, 3);
});

const clockwiseLoop = [[0, 0], [400, 0], [400, 400], [0, 400], [0, 0]];

test("places arrows outside a single loop in either direction", () => {
  assert.deepEqual(loopExteriorSides(clockwiseLoop, [120, 600, 1000, 1400]), [-1, -1, -1, -1]);
  assert.deepEqual(loopExteriorSides([...clockwiseLoop].reverse(), [120, 600, 1000, 1400]), [1, 1, 1, 1]);
  assert.ok(chevronPlacements(clockwiseLoop).every((placement) => placement.side === -1));
});

test("keeps approach and exit arrows on the default side", () => {
  const route = [[-400, 0], ...clockwiseLoop, [0, -400]];
  assert.deepEqual(loopExteriorSides(route, [100, 520, 1000, 1400, 1800, 2200]), [1, -1, -1, -1, -1, 1]);
});

test("gives each lobe its own exterior, including a crossing between sparse edges", () => {
  const eight = [...clockwiseLoop, [0, -400], [-400, -400], [-400, 0], [0, 0]];
  assert.deepEqual(loopExteriorSides(eight, [120, 600, 1000, 1400, 1720, 2200, 2600, 3000]), [-1, -1, -1, -1, 1, 1, 1, 1]);
  const crossing = [[0, 0], [400, 400], [0, 400], [400, 0], [0, 0]];
  assert.deepEqual(loopExteriorSides(crossing, [200, 500, 765, 1165, 1450, 1800]), [1, -1, -1, -1, 1, 1]);
});

test("ignores retracing and open hairpins instead of inventing an exterior", () => {
  assert.deepEqual(loopExteriorSides([[0, 0], [400, 0], [0, 0]], [120, 600]), [1, 1]);
  assert.deepEqual(loopExteriorSides([[0, 0], [400, 0], [400, 20], [0, 20]], [120, 600]), [1, 1]);
});

test("tolerates an approximate closure and is independent of projection origin and scale", () => {
  const loop = [...clockwiseLoop.slice(0, -1), [0, 6]];
  assert.deepEqual(loopExteriorSides(loop, [120, 600, 1000, 1400]), [-1, -1, -1, -1]);
  const scaled = loop.map(([x, y]) => [1e9 + x * 2, -1e9 + y * 2]);
  assert.deepEqual(loopExteriorSides(scaled, [240, 1200, 2000, 2800], { closure: 20 }), [-1, -1, -1, -1]);
});

test("keeps repeated-lap arrows on the exterior", () => {
  const repeated = [...clockwiseLoop, ...clockwiseLoop.slice(1), ...clockwiseLoop.slice(1)];
  assert.ok(chevronPlacements(repeated).every((placement) => placement.side === -1));
});

test("preserves an inner loop's winding when an outer loop closes later", () => {
  const nested = [[0, 0], [1000, 0], [1000, 200], [600, 200], [600, 600], [1000, 600], [1000, 200], [1000, 1000], [0, 1000], [0, 0]];
  assert.deepEqual(loopExteriorSides(nested, [120, 1320, 1800, 2200, 2600, 3000, 4200, 5400]), [-1, 1, 1, 1, 1, -1, -1, -1]);
});

test("draws the chevron pointing east, the direction the rotate angle uses", () => {
  const tip = CHEVRON_POINTS[1];

  assert.equal(CHEVRON_POINTS.length, 3);
  assert.equal(Math.max(...CHEVRON_POINTS.map((point) => point.x)), tip.x);
  assert.equal(CHEVRON_POINTS[0].y + CHEVRON_POINTS[2].y, tip.y * 2);
});

test("adds the icon once and tolerates a map or a canvas that is absent", () => {
  const added = [];
  const map = {
    images: new Set(),
    hasImage(id) { return this.images.has(id); },
    addImage(id, image, options) { added.push({ id, image, options }); this.images.add(id); },
  };

  assert.equal(ensureDirectionImage(null), false);
  assert.equal(ensureDirectionImage(map, { surface: "#fff", track: "#c5426c" }), false);
  assert.equal(added.length, 0);
});

test("anchors geographic lines and shares marks only in the same direction", () => {
  // About 3.3 km due north at 45° N; at zoom 14 that is ~1 150 screen pixels.
  const northward = Array.from({ length: 31 }, (_, index) => [ 6.0, 45.0 + index * 0.001 ]);
  const southward = [ ...northward ].reverse();

  const alone = geographicChevronFeatures([ northward ], { zoom: 14 });
  const same = geographicChevronFeatures([ northward, northward ], { zoom: 14 });
  const opposite = geographicChevronFeatures([ northward, southward ], { zoom: 14, properties: (index) => ({ shade: index }) });

  assert.ok(alone.length >= 3);
  assert.equal(same.length, alone.length);
  assert.equal(opposite.length, alone.length * 2);
  assert.deepEqual(new Set(opposite.map((feature) => feature.properties.shade)), new Set([ 0, 1 ]));
  assert.ok(alone.every((feature) => Math.abs(feature.geometry.coordinates[0] - 6.0) < 1e-9));
});

test("places one arrow on a short course and none on a few pixels", () => {
  const short = [ [ 6.0, 45.0 ], [ 6.0, 45.003 ] ];

  assert.equal(geographicChevronFeatures([ short ], { zoom: 15 }).length, 1);
  assert.equal(geographicChevronFeatures([ short ], { zoom: 8 }).length, 0);
});

test("names its layer and image when a map carries several", () => {
  const layer = directionLayer({ source: "courses", id: "courses-arrows", image: [ "get", "arrow" ] });

  assert.equal(layer.id, "courses-arrows");
  assert.deepEqual(layer.layout["icon-image"], [ "get", "arrow" ]);
});

test("centres an inline mark on the line instead of offsetting it", () => {
  assert.deepEqual(directionLayer({ source: "courses", inline: true }).layout["icon-offset"], [ "literal", [ 0, 0 ] ]);
  assert.deepEqual(directionLayer({ source: "courses" }).layout["icon-offset"][0], "case");
  // The head is centred on the anchor, pointing east like the offset one.
  const xs = INLINE_CHEVRON_POINTS.map((point) => point.x);
  assert.equal((Math.min(...xs) + Math.max(...xs)) / 2, 12);
  assert.equal(Math.max(...xs), INLINE_CHEVRON_POINTS[1].x);
});
