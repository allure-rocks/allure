import assert from "node:assert/strict";
import test from "node:test";

import {
  staticRouteResourceAllowed,
  validateStaticRouteInput,
} from "../../app/frontend/lib/static_route_renderer.js";
import { worldBackground, worldPaint } from "../../app/frontend/lib/virtual_world.js";

test("validates and unwraps a multi-segment route across the antimeridian", () => {
  const route = validateStaticRouteInput({
    segments: [
      [[179.9, 45], [-179.9, 45.1]],
      [[-179.8, 45.2], [-179.7, 45.3]],
    ],
    lineColour: "#206bc4",
    styleUrl: "https://tiles.example.test/style.json",
    allowedOrigins: ["https://cdn.example.test:8443"],
  });

  assert.deepEqual(route.segments, [
    [[179.9, 45], [180.1, 45.1]],
    [[180.2, 45.2], [180.3, 45.3]],
  ]);
  assert.deepEqual(route.allowedOrigins, ["https://cdn.example.test:8443"]);
});

test("rejects invalid coordinates, colours, style URLs, and resource origins", () => {
  const valid = {
    segments: [[[6.4, 45], [6.5, 45.1]]],
    lineColour: "#206bc4",
    styleUrl: "https://tiles.example.test/style.json",
  };

  assert.throws(() => validateStaticRouteInput({ ...valid, segments: [[[181, 45], [6.5, 45.1]]] }), /finite/);
  assert.throws(() => validateStaticRouteInput({ ...valid, lineColour: "blue" }), /lineColour/);
  assert.throws(() => validateStaticRouteInput({ ...valid, styleUrl: "file:///tmp/style.json" }), /HTTP/);
  assert.throws(() => validateStaticRouteInput({ ...valid, allowedOrigins: ["host/path"] }), /origins/);
});

test("bounds large routes while preserving their endpoints", () => {
  const points = Array.from({ length: 10_000 }, (_, index) => [
    6 + index * 0.00001,
    45 + Math.sin(index / 25) * 0.001,
  ]);
  const route = validateStaticRouteInput({
    segments: [points],
    lineColour: "#206bc4",
    styleUrl: "https://tiles.example.test/style.json",
  });

  assert.ok(route.segments[0].length <= 2_000);
  assert.deepEqual(route.segments[0][0], points[0]);
  assert.deepEqual(route.segments[0].at(-1), points.at(-1));
});

test("accepts a display smoothing level and rejects an unknown one", () => {
  const base = {
    segments: [[[6.4, 45], [6.5, 45.1]]],
    lineColour: "#206bc4",
    styleUrl: "https://tiles.example.test/style.json",
  };

  assert.equal(validateStaticRouteInput({ ...base, smoothing: "medium" }).smoothing, "medium");
  assert.equal(validateStaticRouteInput({ ...base, smoothing: "off" }).smoothing, null);
  assert.equal(validateStaticRouteInput(base).smoothing, null);
  assert.throws(() => validateStaticRouteInput({ ...base, smoothing: "extreme" }), /smoothing/);
});

test("accepts a light or dark surface and rejects an unknown theme", () => {
  const base = {
    segments: [[[6.4, 45], [6.5, 45.1]]],
    lineColour: "#206bc4",
    styleUrl: "https://tiles.example.test/style.json",
  };

  assert.equal(validateStaticRouteInput({ ...base, theme: "dark" }).surface, "#171717");
  assert.equal(validateStaticRouteInput({ ...base, theme: "dark" }).ring, "#171717");
  assert.equal(validateStaticRouteInput({ ...base, theme: "light" }).surface, "#f4f6fa");
  assert.equal(validateStaticRouteInput({ ...base, theme: "light" }).ring, "#ffffff");
  assert.equal(validateStaticRouteInput(base).theme, "light");
  assert.throws(() => validateStaticRouteInput({ ...base, theme: "sepia" }), /theme/);
});

test("allows only exact approved origins without HTTPS downgrades", () => {
  const policy = {
    localOrigin: "http://127.0.0.1:4321",
    styleUrl: "https://tiles.example.test/style.json",
    allowedOrigins: ["https://fonts.example.test:8443"],
  };

  assert.equal(staticRouteResourceAllowed("http://127.0.0.1:4321/renderer.js", policy), true);
  assert.equal(staticRouteResourceAllowed("https://tiles.example.test/tile.pbf", policy), true);
  assert.equal(staticRouteResourceAllowed("https://fonts.example.test:8443/font.pbf", policy), true);
  assert.equal(staticRouteResourceAllowed("https://fonts.example.test/font.pbf", policy), false);
  assert.equal(staticRouteResourceAllowed("http://tiles.example.test/tile.pbf", policy), false);
  assert.equal(staticRouteResourceAllowed("https://other.example.test/tile.pbf", policy), false);
});

test("draws a virtual world image instead of a tile style", () => {
  const world = {
    image: "data:image/webp;base64,UklGRg==",
    coordinates: [[166.87747, -11.62597], [167.03255, -11.62597], [167.03255, -11.74087], [166.87747, -11.74087]],
    background: "#0884e2",
    darkBackground: "#032a48",
    attribution: "© Zwift",
  };
  const route = validateStaticRouteInput({
    segments: [[[166.95, -11.63], [166.96, -11.64]]],
    lineColour: "#c5426c",
    virtualBasemap: world,
    theme: "dark",
  });

  assert.equal(route.styleUrl, null);
  assert.equal(route.attribution, "© Zwift");
  assert.equal(route.style.sources["allure-world"].type, "image");
  assert.equal(route.style.sources["allure-world"].url, world.image);
  assert.deepEqual(route.style.sources["allure-world"].coordinates, world.coordinates);
  assert.equal(route.style.layers[0].paint["background-color"], "#032a48");
  assert.equal(route.style.layers[1].paint["raster-brightness-max"], 0.5);

  const light = validateStaticRouteInput({
    segments: [[[6.4, 45], [6.5, 45.1]]],
    lineColour: "#c5426c",
    virtualBasemap: world,
  });
  assert.equal(light.style.layers[0].paint["background-color"], "#0884e2");
  assert.equal(light.style.layers[1].paint["raster-brightness-max"], 1);
});

test("uses the world's dimmed background in dark mode", () => {
  const world = { background: "#0884e2", darkBackground: "#032a48" };

  assert.equal(worldBackground(world, "dark"), "#032a48");
  assert.equal(worldBackground(world, "light"), "#0884e2");
  // Older payloads have no dark background; the light one is the fallback.
  assert.equal(worldBackground({ background: "#0884e2" }, "dark"), "#0884e2");
});

test("resets every raster property when the theme returns to light", () => {
  const dark = worldPaint("dark");
  const light = worldPaint("light");

  for (const property of Object.keys(dark)) {
    assert.notEqual(light[property], undefined, `${property} must be reset`);
  }
  assert.equal(light["raster-brightness-max"], 1);
  assert.equal(light["raster-saturation"], 0);
  assert.equal(light["raster-contrast"], 0);
});

test("rejects a malformed virtual world image", () => {
  const base = {
    segments: [[[6.4, 45], [6.5, 45.1]]],
    lineColour: "#c5426c",
    virtualBasemap: {
      image: "data:image/webp;base64,UklGRg==",
      coordinates: [[6, 45], [7, 45], [7, 44], [6, 44]],
      background: "#0884e2",
    },
  };

  assert.throws(() => validateStaticRouteInput({ ...base, virtualBasemap: { ...base.virtualBasemap, image: "https://cdn.example.test/world.webp" } }), /data URL/);
  assert.throws(() => validateStaticRouteInput({ ...base, virtualBasemap: { ...base.virtualBasemap, background: "blue" } }), /background/);
  assert.throws(() => validateStaticRouteInput({ ...base, virtualBasemap: { ...base.virtualBasemap, darkBackground: "blue" } }), /darkBackground/);
  assert.throws(() => validateStaticRouteInput({ ...base, virtualBasemap: { ...base.virtualBasemap, coordinates: [[6, 45]] } }), /four/);
  assert.throws(() => validateStaticRouteInput({ ...base, virtualBasemap: "world" }), /object/);
});

test("allows a local resource without a style URL", () => {
  const policy = { localOrigin: "http://127.0.0.1:4321", styleUrl: null };

  assert.equal(staticRouteResourceAllowed("http://127.0.0.1:4321/world.webp", policy), true);
  assert.equal(staticRouteResourceAllowed("https://other.example.test/world.webp", policy), false);
});
