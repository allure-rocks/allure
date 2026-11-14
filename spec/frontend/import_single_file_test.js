import assert from "node:assert/strict";
import test from "node:test";

import { singleImportFiles } from "../../app/frontend/lib/import_single_file.js";

const file = (name) => ({ name });

test("a bare track file is a single import", () => {
  assert.equal(singleImportFiles([ file("ride.gpx") ]), true);
  assert.equal(singleImportFiles([ file("ride.GPX") ]), true);
  assert.equal(singleImportFiles([ file("ride.fit") ]), true);
  assert.equal(singleImportFiles([ file("ride.tcx") ]), true);
  assert.equal(singleImportFiles([ file("ride.kml") ]), true);
});

test("a gzip-compressed file and a KMZ hold one entry each", () => {
  assert.equal(singleImportFiles([ file("ride.fit.gz") ]), true);
  assert.equal(singleImportFiles([ file("ride.gpx.gz") ]), true);
  assert.equal(singleImportFiles([ file("track.kmz") ]), true);
});

test("a ZIP can hold several entries and never reveals the title", () => {
  assert.equal(singleImportFiles([ file("archive.zip") ]), false);
  assert.equal(singleImportFiles([ file("archive.ZIP") ]), false);
});

test("anything but exactly one file is not a single import", () => {
  assert.equal(singleImportFiles([ file("one.gpx"), file("two.gpx") ]), false);
  assert.equal(singleImportFiles([]), false);
  assert.equal(singleImportFiles(null), false);
  assert.equal(singleImportFiles(undefined), false);
});
