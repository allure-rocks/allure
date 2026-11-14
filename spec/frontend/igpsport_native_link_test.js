import assert from "node:assert/strict";
import test from "node:test";

import { NativeLink, concat, decodeBase64 } from "../../app/frontend/lib/igpsport/native_link.js";

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

  get last() {
    return this.requests.length - 1;
  }
}

function fixture() {
  const bridge = new FakeBridge();
  const logs = [];
  let disconnects = 0;
  const link = new NativeLink({
    bridge,
    onLog: (message, kind) => logs.push([message, kind ?? ""]),
    onDisconnect: () => { disconnects += 1; },
  });
  return { bridge, link, logs, disconnects: () => disconnects };
}

test("connect resolves on the connected reply and keeps the handshake report", async () => {
  const { bridge, link, logs } = fixture();

  const connecting = link.connect();
  assert.deepEqual(bridge.requests.map((request) => request.event), ["connect"]);
  bridge.reply(0, { status: "log", message: "scanning", kind: "" });
  bridge.reply(0, { status: "connected", name: "BSC500", serial: "0042", battery: 87 });
  await connecting;

  assert.deepEqual(await link.initialize(), {
    model: { name: "BSC500", verified: true },
    serial: "0042",
    battery: 87,
  });
  assert.deepEqual(logs, [["scanning", ""], ["connected to BSC500", ""]]);
});

test("a computer the web does not know is reported as untested, not refused", async () => {
  for (const [name, model] of [
    ["iGS800", { name: "iGS800", verified: false }],
    ["BSC700", { name: "BSC700", verified: false }],
    [undefined, null],
  ]) {
    const { bridge, link } = fixture();
    const connecting = link.connect();
    bridge.reply(0, { status: "connected", name, serial: "1", battery: 50 });
    await connecting;

    assert.deepEqual((await link.initialize()).model, model, String(name));
  }
});

test("connect rejects when the app fails or the chooser is cancelled", async () => {
  const { bridge, link } = fixture();

  const connecting = link.connect();
  bridge.reply(0, { status: "cancelled" });
  await assert.rejects(connecting, /Connection cancelled/);

  const retrying = link.connect();
  bridge.reply(1, { status: "failed", error: "Turn on Bluetooth" });
  await assert.rejects(retrying, /Turn on Bluetooth/);
  await assert.rejects(link.initialize(), /not connected/);
});

test("listActivities returns the app's entries", async () => {
  const { bridge, link } = fixture();

  const listing = link.listActivities();
  bridge.reply(0, { status: "listed", activities: [{ timestamp: 1073001600, fileSize: 1024 }] });

  assert.deepEqual(await listing, { activities: [{ timestamp: 1073001600, fileSize: 1024 }] });

  const failing = link.listActivities();
  bridge.reply(1, { status: "failed", error: "No response" });
  await assert.rejects(failing, /No response/);
});

test("downloadActivity reassembles the chunks in index order and reports progress", async () => {
  const { bridge, link } = fixture();
  const progress = [];

  const downloading = link.downloadActivity({ timestamp: 1072915200, fileSize: 6 }, (received, expected) => {
    progress.push([received, expected]);
  });
  assert.deepEqual(bridge.requests[0].data, { timestamp: 1072915200, fileSize: 6 });
  bridge.reply(0, { status: "progress", received: 2, expected: 6 });
  bridge.reply(0, { status: "chunk", index: 1, count: 2, data: Buffer.from([4, 5, 6]).toString("base64") });
  bridge.reply(0, { status: "chunk", index: 0, count: 2, data: Buffer.from([1, 2, 3]).toString("base64") });
  bridge.reply(0, { status: "complete", fileSize: 6, fileId: 7, fileName: "ride.fit", fileCrc32: 12345 });

  const { metadata, content } = await downloading;
  assert.deepEqual(Array.from(content), [1, 2, 3, 4, 5, 6]);
  assert.deepEqual(metadata, { fileSize: 6, fileId: 7, fileName: "ride.fit", fileCrc32: 12345 });
  assert.deepEqual(progress, [[2, 6], [6, 6]]);
});

test("downloadActivity rejects on a failed reply", async () => {
  const { bridge, link } = fixture();

  const downloading = link.downloadActivity({ timestamp: 1 });
  bridge.reply(0, { status: "failed", error: "FIT file CRC mismatch" });

  await assert.rejects(downloading, /CRC mismatch/);
});

test("disconnect tells the app once and resets the panel at once", async () => {
  const { bridge, link, disconnects } = fixture();
  const connecting = link.connect();
  bridge.reply(0, { status: "connected", name: "BSC500-0042" });
  await connecting;

  link.disconnect();
  link.disconnect();

  assert.deepEqual(bridge.requests.map((request) => request.event), ["connect", "disconnect"]);
  assert.equal(disconnects(), 1);
  assert.equal(link.connected, false);
});

test("an unexpected disconnection reported by the app resets the panel", async () => {
  const { bridge, link, disconnects } = fixture();
  const connecting = link.connect();
  bridge.reply(0, { status: "connected", name: "BSC500-0042" });
  await connecting;

  bridge.reply(0, { status: "disconnected" });
  link.disconnect();

  assert.equal(disconnects(), 1);
  assert.deepEqual(bridge.requests.map((request) => request.event), ["connect"]);
});

test("base64 helpers decode and join chunks", () => {
  assert.deepEqual(Array.from(decodeBase64(Buffer.from([0, 255, 16]).toString("base64"))), [0, 255, 16]);
  assert.deepEqual(Array.from(concat([new Uint8Array([1]), undefined, new Uint8Array([2, 3])])), [1, 2, 3]);
});
