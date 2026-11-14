import assert from "node:assert/strict";
import test from "node:test";

import { SharedFiles } from "../../app/frontend/lib/shared_files.js";

// A scripted bridge: every request is recorded, and the test answers it by
// calling the registered callback like the app's replies would.
class FakeBridge {
  constructor() {
    this.requests = [];
  }

  request(event, data, onReply) {
    this.requests.push({ event, data, onReply });
  }

  reply(index, data) {
    this.requests[index].onReply(data);
  }
}

const b64 = (bytes) => Buffer.from(bytes).toString("base64");

// The transfer asks for each file after the manifest resolves, so one
// macrotask separates a reply from the next recorded request.
const flush = () => new Promise((resolve) => setImmediate(resolve));

test("fetch returns no files when the app holds none", async () => {
  const bridge = new FakeBridge();
  const transfer = new SharedFiles({ bridge });

  const fetching = transfer.fetch();
  assert.deepEqual(bridge.requests.map((request) => request.event), ["connect"]);

  bridge.reply(0, { status: "empty" });
  assert.deepEqual(await fetching, []);
});

test("fetch returns a File per entry with its bytes reassembled in order", async () => {
  const bridge = new FakeBridge();
  const transfer = new SharedFiles({ bridge });

  const fetching = transfer.fetch();
  bridge.reply(0, {
    status: "files",
    files: [
      { index: 0, name: "ride.gpx", type: "application/gpx+xml" },
      { index: 1, name: "walk.fit" },
    ],
  });
  await flush();
  assert.deepEqual(bridge.requests[1].data, { index: 0 });

  bridge.reply(1, { status: "chunk", index: 1, count: 2, data: b64([4, 5, 6]) });
  bridge.reply(1, { status: "chunk", index: 0, count: 2, data: b64([1, 2, 3]) });
  bridge.reply(1, { status: "complete" });
  await flush();
  assert.deepEqual(bridge.requests[2].data, { index: 1 });

  bridge.reply(2, { status: "chunk", index: 0, count: 1, data: b64([9]) });
  bridge.reply(2, { status: "complete" });

  const files = await fetching;
  assert.equal(files.length, 2);
  assert.equal(files[0].name, "ride.gpx");
  assert.equal(files[0].type, "application/gpx+xml");
  assert.deepEqual(Array.from(new Uint8Array(await files[0].arrayBuffer())), [1, 2, 3, 4, 5, 6]);
  assert.equal(files[1].name, "walk.fit");
  assert.equal(files[1].type, "application/octet-stream");
  assert.deepEqual(Array.from(new Uint8Array(await files[1].arrayBuffer())), [9]);
});

test("fetch rejects when the app fails a transfer", async () => {
  const bridge = new FakeBridge();
  const transfer = new SharedFiles({ bridge });

  const fetching = transfer.fetch();
  bridge.reply(0, { status: "files", files: [{ index: 0, name: "ride.gpx" }] });
  await flush();
  bridge.reply(1, { status: "failed", error: "Unreadable file" });

  await assert.rejects(fetching, /Unreadable file/);
});
