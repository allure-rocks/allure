import assert from "node:assert/strict";
import test from "node:test";

import { overlayAnchorLayerId } from "../../app/frontend/lib/map_overlay_anchor.js";

// Representative prefix of OpenFreeMap liberty: the first symbol is a
// minzoom-16 one-way arrow, and every bridge, building and boundary layer
// follows it. The anchor must clear all of them.
const liberty = [
  { id: "background", type: "background" },
  { id: "road_trunk_primary", type: "line" },
  { id: "road_one_way_arrow", type: "symbol", minzoom: 16 },
  { id: "bridge_motorway", type: "line" },
  { id: "building", type: "fill", minzoom: 13, maxzoom: 14 },
  { id: "building-3d", type: "fill-extrusion", minzoom: 14 },
  { id: "boundary_2", type: "line" },
  { id: "waterway_line_label", type: "symbol" },
  { id: "place_city", type: "symbol" },
];

// Representative prefix of OpenFreeMap dark: water_name is a symbol on top of
// nothing, and all roads, railways and boundaries are declared after it.
const dark = [
  { id: "water_name", type: "symbol" },
  { id: "building", type: "fill", minzoom: 12 },
  { id: "highway_motorway_inner", type: "line" },
  { id: "road_oneway", type: "symbol", minzoom: 15 },
  { id: "highway_motorway_subtle", type: "line" },
  { id: "railway", type: "line", minzoom: 13 },
  { id: "highway_name_other", type: "symbol" },
  { id: "boundary_state", type: "line" },
  { id: "place_other", type: "symbol" },
];

test("anchors after the last geometry layer of the liberty style", () => {
  assert.equal(overlayAnchorLayerId(liberty), "waterway_line_label");

  const anchor = liberty.findIndex((layer) => layer.id === "waterway_line_label");
  assert.ok(liberty.slice(anchor).every((layer) => layer.type === "symbol"));
});

test("anchors after the last geometry layer of the dark style", () => {
  assert.equal(overlayAnchorLayerId(dark), "place_other");

  const anchor = dark.findIndex((layer) => layer.id === "place_other");
  assert.ok(dark.slice(anchor).every((layer) => layer.type === "symbol"));
});

test("appends above every layer when the style has no trailing symbol", () => {
  assert.equal(overlayAnchorLayerId([
    { id: "background", type: "background" },
    { id: "water", type: "fill" },
    { id: "road", type: "line" },
  ]), undefined);
});

test("appends above every layer when the style has no layers", () => {
  assert.equal(overlayAnchorLayerId([]), undefined);
  assert.equal(overlayAnchorLayerId(undefined), undefined);
});
