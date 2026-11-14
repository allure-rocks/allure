import assert from "node:assert/strict";
import test from "node:test";

import { cropRect, cropSide, layout, maxZoom, panBy, placement, zoomAround } from "../../app/frontend/lib/avatar_crop.js";

test("keeps the short side at the smallest zoom", () => {
  assert.deepEqual(cropRect({ width: 400, height: 300, zoom: 1, centreX: 200, centreY: 150 }), { left: 50, top: 0, side: 300 });
  assert.equal(cropSide({ width: 400, height: 300, zoom: 2 }), 150);
});

test("clamps the square inside the image", () => {
  assert.deepEqual(cropRect({ width: 400, height: 300, zoom: 2, centreX: 0, centreY: 1000 }), { left: 0, top: 150, side: 150 });
});

test("drags the window the other way and stops at the edge", () => {
  const state = { width: 400, height: 300, zoom: 2, centreX: 200, centreY: 150, stageSize: 300 };

  const moved = panBy({ ...state, dx: 30, dy: -15 });
  assert.equal(moved.centreX, 185);
  assert.equal(moved.centreY, 157.5);

  assert.equal(panBy({ ...state, dx: 10000, dy: 0 }).centreX, 75);
});

test("zooms around the pointer and stops at the bounds", () => {
  const state = { width: 400, height: 300, zoom: 1, centreX: 200, centreY: 150, stageSize: 300 };

  const zoomed = zoomAround({ ...state, nextZoom: 2, anchorX: 0, anchorY: 0 });
  assert.equal(zoomed.zoom, 2);
  assert.equal(zoomed.centreX, 125);
  assert.equal(zoomed.centreY, 75);

  assert.equal(zoomAround({ ...state, nextZoom: 100, anchorX: 150, anchorY: 150 }).zoom, maxZoom(state));
});

test("lays the image out under the window", () => {
  const view = layout({ width: 400, height: 300, zoom: 2, centreX: 200, centreY: 150, stageSize: 300 });

  assert.equal(view.scale, 2);
  assert.equal(view.width, 800);
  assert.equal(view.height, 600);
  assert.equal(view.left, -250);
  assert.equal(view.top, -150);
});

test("sends whole pixels of the oriented image", () => {
  assert.deepEqual(placement({ left: 12.4, top: 0.6, side: 100.5 }), { x: 12, y: 1, size: 101 });
});
