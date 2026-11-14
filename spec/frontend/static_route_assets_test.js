import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";

// `script/render-static-route` serves the renderer and its modules from an
// explicit allowlist because Chromium loads them over HTTP. A module added to
// the renderer but not to that allowlist fails only inside the headless
// browser, as `window.renderRoute is not a function`, which no unit test would
// otherwise see. Walk the renderer's local imports and require each one.
const RUNNER = readFileSync(new URL("../../script/render-static-route", import.meta.url), "utf8");
const LIB = new URL("../../app/frontend/lib/", import.meta.url);

function localImports(source) {
  return [...source.matchAll(/from\s+"\.\/([^"]+)"/g)].map((match) => match[1]);
}

test("the static route server serves every module the renderer imports", () => {
  const pending = ["static_route_renderer.js"];
  const seen = new Set();
  const missing = [];

  while (pending.length > 0) {
    const name = pending.pop();
    if (seen.has(name)) continue;
    seen.add(name);

    const source = readFileSync(new URL(name, LIB), "utf8");
    for (const imported of localImports(source)) {
      const fileName = imported.replace(/^\.\//, "");
      pending.push(fileName);
      if (!RUNNER.includes(`/${fileName}`)) missing.push(fileName);
    }
  }

  assert.deepEqual(missing, []);
  assert.ok(seen.size >= 3);
});
