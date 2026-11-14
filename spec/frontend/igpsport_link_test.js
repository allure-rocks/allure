import assert from "node:assert/strict";
import test from "node:test";

import { bytesFromHex, concatMany } from "../../app/frontend/lib/igpsport/bytes.js";
import { NUS_CHANNELS } from "../../app/frontend/lib/igpsport/constants.js";
import { craftData, parseHeader } from "../../app/frontend/lib/igpsport/framing.js";
import { Bsc500Link } from "../../app/frontend/lib/igpsport/link.js";
import { NAME_PREFIXES, resolveModel } from "../../app/frontend/lib/igpsport/models.js";
import { bytesField, varintField } from "../../app/frontend/lib/igpsport/protobuf.js";

// Frames captured from a BSC100S by the iGadgetBridge lab
// (tests/test_channel_reassembly.py): MTU 23 splits the LIST_NUM_GET reply
// into a bare header and its payload (17 activities, pages of 20), and a stray
// FILE_SEND result follows it.
const BSC100S_LIST_NUM_NOTIFICATIONS = [
  "0106FFFF08FFFF000A0101FFFFFFFFFFFFFFFF5F",
  "08061008320408111014",
];
const TRAILING_RESULT = "0206FFFF04FFFF01FFFFFFFFFFFFFFFFFFFFFF46";

// Shared with the companion's IgpsportProtocolTests.
const ACCEPTED_NAMES = [
  "BSC500", "BSC100S", "BSC100", "BSC100Max", "BSC200", "BSC200S", "BSC300", "BSC300T",
  "iGS630", "iGS630S", "iGS800", "BiNavi", "BiNavi Air", "iGPSPORT BiNavi Air", "iGPSPORT BINAVI_AIR",
];
const REFUSED_NAMES = ["", "BSC", "BSC600", "iGS620", "iGS320", "iGPSPORT", "iGPSPORT VS1200S", "HR70", "Edge 530"];

const notFound = () => Object.assign(new Error("No Services matching UUID found in Device."), { name: "NotFoundError" });

class FakeCharacteristic {
  constructor(uuid) {
    this.uuid = uuid;
    this.value = null;
    this.listeners = [];
    this.writes = [];
    this.onWrite = null;
  }

  addEventListener(_type, listener) {
    this.listeners.push(listener);
  }

  async startNotifications() {}

  async writeValueWithResponse(value) {
    const bytes = Uint8Array.from(value);
    this.writes.push(bytes);
    this.onWrite?.(bytes);
  }

  notify(bytes) {
    this.value = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    for (const listener of this.listeners) listener({ target: this });
  }
}

// A computer behind Web Bluetooth: it reassembles each request from the
// acknowledged pieces, answers through `respond`, and notifies at most
// `notifySize` bytes at a time, as its MTU allows.
class FakeComputer {
  constructor({ name, channels = [1, 2, 3, 4, 5], notifySize = 244, respond = () => [] }) {
    this.name = name;
    this.notifySize = notifySize;
    this.respond = respond;
    this.requests = [];
    this.characteristics = new Map();
    this.pieces = new Map();
    this.connected = false;
    this.requestedOptions = null;
    this.listeners = [];

    for (const channel of NUS_CHANNELS.filter((item) => channels.includes(item.number))) {
      const tx = new FakeCharacteristic(channel.tx);
      const rx = new FakeCharacteristic(channel.rx);
      tx.onWrite = (bytes) => this.receive(channel.number, bytes);
      this.characteristics.set(channel.number, { service: channel.service, tx, rx });
    }
  }

  get bluetooth() {
    return {
      requestDevice: async (options) => {
        this.requestedOptions = options;
        return this.device;
      },
    };
  }

  get device() {
    const computer = this;
    return {
      name: this.name,
      addEventListener: (_type, listener) => computer.listeners.push(listener),
      gatt: {
        get connected() { return computer.connected; },
        connect: async () => {
          computer.connected = true;
          return computer.server;
        },
        disconnect: () => {
          computer.connected = false;
          for (const listener of computer.listeners) listener();
        },
      },
    };
  }

  get server() {
    const computer = this;
    return {
      get connected() { return computer.connected; },
      getPrimaryService: async (uuid) => {
        const entry = [...computer.characteristics.values()].find((item) => item.service === uuid);
        if (!entry) throw notFound();
        return {
          getCharacteristic: async (characteristic) => {
            if (characteristic === entry.tx.uuid) return entry.tx;
            if (characteristic === entry.rx.uuid) return entry.rx;
            throw notFound();
          },
        };
      },
    };
  }

  writes(channel) {
    return this.characteristics.get(channel).tx.writes;
  }

  receive(channel, bytes) {
    let buffer = concatMany([this.pieces.get(channel) ?? new Uint8Array(), bytes]);
    while (buffer.length >= 20) {
      const header = parseHeader(buffer);
      const size = 20 + header.size;
      if (buffer.length < size) break;

      const request = { channel, header, payload: buffer.slice(20, size) };
      this.requests.push(request);
      buffer = buffer.slice(size);
      const replies = this.respond(request);
      setImmediate(() => replies.forEach((reply) => this.send(channel, reply)));
    }
    this.pieces.set(channel, buffer);
  }

  // A reply given as a list is sent notification by notification, as captured.
  send(channel, reply) {
    const rx = this.characteristics.get(channel).rx;
    if (Array.isArray(reply)) {
      reply.forEach((notification) => rx.notify(bytesFromHex(notification)));
      return;
    }
    for (let offset = 0; offset < reply.length; offset += this.notifySize) {
      rx.notify(reply.slice(offset, offset + this.notifySize));
    }
  }
}

const battery = concatMany([varintField(1, 11), varintField(2, 6), bytesField(6, concatMany([varintField(1, 4012), varintField(2, 87)]))]);
const serial = (value) => concatMany([varintField(1, 11), varintField(2, 1), bytesField(3, bytesField(1, new TextEncoder().encode(value)))]);
const reply = (header, payload = new Uint8Array()) => craftData(header.service, header.command, payload);

function initReplies(request, { serialNumber = "1234567890", versionInfo = true } = {}) {
  const { header } = request;
  if (header.service === 11 && header.command === 6) return [reply(header, battery)];
  if (header.service === 11 && header.command === 1) return [reply(header, serial(serialNumber))];
  if (header.service === 17 && !versionInfo) return [];
  if ([10, 4, 17].includes(header.service)) return [reply(header, new Uint8Array([0x08, header.service]))];
  return null;
}

function stream(content) {
  const metadata = varintField(1, content.length);
  const header = craftData(6, 3, new Uint8Array(), true).slice(0, 20);
  const size = new Uint8Array(4);
  new DataView(size.buffer).setUint32(0, metadata.length, false);
  return concatMany([header, size, metadata, content]);
}

const listing = (timestamps) => concatMany([
  varintField(1, 6),
  varintField(2, 2),
  ...timestamps.map((timestamp) => bytesField(3, concatMany([varintField(1, timestamp), varintField(2, 512)]))),
]);

function link(computer, options = {}) {
  const logs = [];
  const instance = new Bsc500Link({
    bluetooth: computer.bluetooth,
    onLog: (message, kind) => logs.push([message, kind]),
    ...options,
  });
  return { link: instance, logs };
}

test("resolveModel accepts the protocol family and verifies only the tested computers", () => {
  for (const name of ACCEPTED_NAMES) assert.ok(resolveModel(name), name);
  for (const name of REFUSED_NAMES) assert.equal(resolveModel(name), null, name);

  assert.deepEqual(resolveModel("BSC500"), { name: "BSC500", verified: true, writeSize: 244 });
  assert.deepEqual(resolveModel("BSC100S"), { name: "BSC100S", verified: true, writeSize: 20 });
  assert.deepEqual(resolveModel("iGS800"), { name: "iGS800", verified: false, writeSize: 20 });
  assert.equal(resolveModel(null), null);
});

test("every accepted name passes the chooser's prefix filters", () => {
  for (const name of ACCEPTED_NAMES) {
    assert.ok(NAME_PREFIXES.some((prefix) => name.startsWith(prefix)), name);
  }
});

test("connect filters by family prefix and refuses a name outside the family", async () => {
  const computer = new FakeComputer({ name: "iGPSPORT VS1200S" });
  const { link: instance } = link(computer);

  await assert.rejects(instance.connect(), (error) => error.name === "UnsupportedModelError" && error.deviceName === "iGPSPORT VS1200S");
  assert.deepEqual(computer.requestedOptions.filters, NAME_PREFIXES.map((namePrefix) => ({ namePrefix })));
  assert.equal(computer.requestedOptions.optionalServices.length, 5);
  assert.equal(computer.connected, false);
});

test("a computer without the initialization or activity channel is refused", async () => {
  for (const missing of [1, 3]) {
    const computer = new FakeComputer({ name: "BSC300", channels: [1, 2, 3, 4].filter((number) => number !== missing) });
    await assert.rejects(link(computer).link.connect(), new RegExp(`UART channel ${missing} is missing`));
  }
});

test("the BSC100S connects on four channels, writes 20-byte pieces, and lists its activities", async () => {
  const computer = new FakeComputer({
    name: "BSC100S",
    channels: [1, 2, 3, 4],
    notifySize: 20,
    respond: (request) => {
      const init = initReplies(request, { serialNumber: "1234567890123456789" });
      if (init) return init;
      if (request.header.command === 8) return [BSC100S_LIST_NUM_NOTIFICATIONS, [TRAILING_RESULT]];
      if (request.header.service === 6 && request.header.command === 1) return [reply(request.header, listing([1072915200, 1073001600])), [TRAILING_RESULT]];
      return [];
    },
  });
  const { link: instance, logs } = link(computer);

  await instance.connect();
  assert.ok(logs.some(([message]) => message === "ch5 UART service absent; skipped"));

  const report = await instance.initialize();
  assert.deepEqual(report, {
    model: { name: "BSC100S", verified: true },
    voltage: 4012,
    battery: 87,
    serial: "1234567890123456789",
  });

  const { count, activities } = await instance.listActivities();
  assert.deepEqual(count, { fileCount: 17, pageSize: 20 });
  assert.deepEqual(activities.map((activity) => activity.timestamp), [1073001600, 1072915200]);

  const pages = computer.requests.filter((request) => request.header.service === 6 && request.header.command === 1);
  assert.equal(pages.length, 1);
  for (const channel of [1, 3]) {
    assert.ok(computer.writes(channel).every((piece) => piece.length <= 20));
  }
  assert.ok(computer.writes(1).length > computer.requests.filter((request) => request.channel === 1).length);
});

test("a BSC100S download starting with a bare header is copied whole, with throttled progress", async () => {
  const content = Uint8Array.from({ length: 5000 }, (_, index) => index % 251);
  const computer = new FakeComputer({
    name: "BSC100S",
    channels: [1, 2, 3, 4],
    notifySize: 20,
    respond: (request) => (request.header.command === 3 ? [stream(content), [TRAILING_RESULT]] : initReplies(request) ?? []),
  });
  const { link: instance } = link(computer);
  await instance.connect();
  await instance.initialize();

  const progress = [];
  const { metadata, content: received } = await instance.downloadActivity(
    { timestamp: 1072915200, fileSize: content.length },
    (bytes, expected) => progress.push([bytes, expected]),
  );

  assert.deepEqual(received, content);
  assert.deepEqual(metadata, { fileSize: content.length, fileId: null, fileName: null, fileCrc32: null });
  assert.ok(progress.length <= 101, `${progress.length} progress updates`);
  assert.deepEqual(progress.at(-1), [content.length, content.length]);
  assert.equal(instance.stream, null);

  // The stray result behind the stream did not disturb the next request.
  const listingRequest = instance.request(3, 6, 8, new Uint8Array([0x08, 0x06]), { fileOperation: true, timeoutMs: 50 });
  await assert.rejects(listingRequest, /No response from service 6/);
});

test("the BSC500 keeps one write per request on its five channels", async () => {
  const computer = new FakeComputer({ name: "BSC500", respond: (request) => initReplies(request) ?? [] });
  const { link: instance } = link(computer);

  await instance.connect();
  await instance.initialize();

  const requests = computer.requests.filter((request) => request.channel === 1);
  assert.equal(requests.length, 5);
  assert.equal(computer.writes(1).length, requests.length);
});

test("an untested model that ignores the version query still completes the handshake", async () => {
  const computer = new FakeComputer({
    name: "iGS800",
    channels: [1, 2, 3, 4],
    respond: (request) => initReplies(request, { versionInfo: false }) ?? [],
  });
  const { link: instance, logs } = link(computer, { timeouts: { request: 30 } });

  await instance.connect();
  const report = await instance.initialize();

  assert.deepEqual(report.model, { name: "iGS800", verified: false });
  assert.equal(report.serial, "1234567890");
  assert.ok(logs.some(([message]) => message === "no reply from service 17; continuing"));
  assert.ok(computer.writes(1).every((piece) => piece.length <= 20));
});

test("a required handshake step that stays silent still fails the connection", async () => {
  const computer = new FakeComputer({
    name: "BSC200",
    respond: (request) => (request.header.service === 11 && request.header.command === 1 ? [] : initReplies(request) ?? []),
  });
  const { link: instance } = link(computer, { timeouts: { request: 30 } });

  await instance.connect();
  await assert.rejects(instance.initialize(), /No response from service 11/);
});
