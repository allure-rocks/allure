import assert from "node:assert/strict";
import test from "node:test";

import { basemapFollowsPage, resolveBasemapTheme } from "../../app/frontend/lib/basemap_theme.js";

test("follows the page theme by default", () => {
  assert.equal(resolveBasemapTheme("auto", "dark"), "dark");
  assert.equal(resolveBasemapTheme("auto", "light"), "light");
  assert.equal(resolveBasemapTheme(undefined, "dark"), "dark");
  assert.equal(resolveBasemapTheme("auto", undefined), "light");
  assert.ok(basemapFollowsPage("auto"));
  assert.ok(basemapFollowsPage(undefined));
});

test("forces the chosen variant whatever the page theme", () => {
  assert.equal(resolveBasemapTheme("light", "dark"), "light");
  assert.equal(resolveBasemapTheme("dark", "light"), "dark");
  assert.equal(basemapFollowsPage("light"), false);
  assert.equal(basemapFollowsPage("dark"), false);
});
