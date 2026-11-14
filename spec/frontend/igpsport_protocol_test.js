import assert from "node:assert/strict";
import test from "node:test";

import { bytesFromHex, concatBytes, concatMany, toHex } from "../../app/frontend/lib/igpsport/bytes.js";
import { crc8Maxim, craftData, parseHeader } from "../../app/frontend/lib/igpsport/framing.js";
import {
  activityCountPayload,
  activityFilePayload,
  activityListPayload,
  bytesField,
  decodeActivityList,
  decodeActivityCount,
  decodeFileMetadata,
  varintField,
} from "../../app/frontend/lib/igpsport/protobuf.js";
import {
  activityFilename,
  crc32,
  fitCrc16,
  validateFit,
} from "../../app/frontend/lib/igpsport/fit.js";

// Golden vectors shared with the iGadgetBridge reference implementation
// (tests/test_crc.py and tests/test_device.py).
test("crc8Maxim matches the captured hardware vectors", () => {
  const vectors = [
    ["080C10141802", 0x4a],
    ["010C14FF02FFFF00064A01FFFFFFFFFFFFFFFF", 0xf0],
    ["0115FFAA03FFFF00000001FFFFFFFFFFFFFFFF", 0x57],
    ["030302FF01FFFF00FFFFFFFFFFFFFFFFFFFFFF", 0x7e],
    ["030305FF01FFFF00FFFFFFFFFFFFFFFFFFFFFF", 0xb3],
    ["030306FF01FFFF00FFFFFFFFFFFFFFFFFFFFFF", 0xc2],
  ];

  for (const [hex, expected] of vectors) {
    assert.equal(crc8Maxim(bytesFromHex(hex)), expected, hex);
  }
  assert.equal(crc8Maxim(new Uint8Array()), 0);
});

test("activity payloads match the protobuf wire bytes", () => {
  assert.equal(toHex(activityCountPayload()), "08061008");
  assert.equal(toHex(activityListPayload(0, 1)), "08061001320418002001");
  assert.equal(toHex(activityFilePayload(1072915200)), "080610031A060880C6CDFF03");
});

test("activity pages reject missing or inverted bounds", () => {
  assert.throws(() => activityListPayload(2, 1), /0 <= start <= end/);
  assert.throws(() => activityListPayload(0, undefined), /0 <= start <= end/);
});

test("craftData lays out the header, sizes, and both CRCs", () => {
  const payload = activityCountPayload();
  const packet = craftData(6, 8, payload, true);

  assert.equal(packet[0], 0x01);
  assert.equal(packet[1], 6);
  assert.equal(packet[3], 0x55);
  assert.equal(packet[4], 8);
  assert.equal((packet[7] << 8) | packet[8], payload.length);
  assert.equal(packet[9], crc8Maxim(payload));
  assert.equal(packet[19], crc8Maxim(packet.subarray(0, 19)));
  assert.deepEqual(packet.slice(20), payload);

  const header = parseHeader(packet);
  assert.deepEqual(header, {
    type: 0x01,
    service: 6,
    mode: 0x55,
    command: 8,
    size: payload.length,
    resultCode: null,
  });
});

test("craftData leaves normal requests in the default mode", () => {
  const packet = craftData(2, 1, new Uint8Array());
  assert.equal(packet[3], 0xff);
  assert.equal(packet.length, 20);
});

test("parseHeader rejects a corrupted header CRC", () => {
  const packet = craftData(6, 8, activityCountPayload());
  packet[19] ^= 0x01;

  assert.throws(() => parseHeader(packet), /Header CRC mismatch/);
});

test("decodeActivityCount reads the paging descriptor", () => {
  const listing = concatMany([varintField(1, 42), varintField(2, 20)]);
  const payload = concatMany([varintField(1, 6), varintField(2, 2), bytesField(6, listing)]);

  assert.deepEqual(decodeActivityCount(payload), { fileCount: 42, pageSize: 20 });
});

test("decodeActivityList drops the zero placeholder and keeps real entries", () => {
  const entry = (timestamp, fileSize) =>
    bytesField(3, concatMany([
      varintField(1, timestamp),
      fileSize === undefined ? new Uint8Array() : varintField(2, fileSize),
    ]));
  const payload = concatMany([
    varintField(1, 6),
    varintField(2, 2),
    entry(1072915200, 204800),
    entry(1073001600),
    entry(0, 0),
  ]);

  assert.deepEqual(decodeActivityList(payload), [
    { timestamp: 1072915200, fileSize: 204800, userId: null, deviceId: null },
    { timestamp: 1073001600, fileSize: null, userId: null, deviceId: null },
  ]);
});

test("decodeFileMetadata requires a file size", () => {
  const valid = concatMany([
    varintField(1, 4096),
    varintField(3, 7),
    bytesField(4, new TextEncoder().encode("a.fit")),
    varintField(8, 12345),
  ]);

  assert.deepEqual(decodeFileMetadata(valid), {
    fileSize: 4096,
    fileId: 7,
    fileName: "a.fit",
    fileCrc32: 12345,
  });
  assert.throws(() => decodeFileMetadata(varintField(3, 7)), /valid file size/);
});

function fitFile(payload = new Uint8Array(16), { headerSize = 14 } = {}) {
  const header = new Uint8Array(headerSize);
  header[0] = headerSize;
  header[1] = 0x20;
  header[2] = 0x1e;
  header[3] = 0x08;
  new DataView(header.buffer).setUint32(4, payload.length, true);
  header.set(new TextEncoder().encode(".FIT"), 8);
  if (headerSize === 14) {
    new DataView(header.buffer).setUint16(12, fitCrc16(header.slice(0, 12)), true);
  }

  const body = concatBytes(header, payload);
  const crc = new Uint8Array(2);
  new DataView(crc.buffer).setUint16(0, fitCrc16(body), true);
  return concatBytes(body, crc);
}

test("validateFit accepts 12- and 14-byte headers and catches corruption", () => {
  const content = fitFile();
  assert.deepEqual(validateFit(content, { fileSize: content.length, fileCrc32: null }), {
    ok: true,
    errors: [],
  });

  const legacy = fitFile(new Uint8Array(16), { headerSize: 12 });
  assert.equal(validateFit(legacy, { fileSize: legacy.length }).ok, true);

  const flipped = content.slice();
  flipped[20] ^= 0x01;
  const result = validateFit(flipped, { fileSize: flipped.length });
  assert.equal(result.ok, false);
  assert.ok(result.errors.some((error) => error.includes("file CRC mismatch")));
});

test("validateFit checks the declared size, device CRC32, and signature", () => {
  const content = fitFile();

  assert.match(
    validateFit(content, { fileSize: content.length + 1 }).errors.join("; "),
    /metadata declares/,
  );

  const deviceCrc = validateFit(content, {
    fileSize: content.length,
    fileCrc32: crc32(content) ^ 0xffff,
  });
  assert.ok(deviceCrc.errors.some((error) => error.includes("device CRC32")));

  const unsigned = content.slice();
  unsigned.set(new TextEncoder().encode("NOPE"), 8);
  assert.ok(validateFit(unsigned, { fileSize: unsigned.length }).errors.some((error) => error.includes("signature")));
});

test("activityFilename uses the UTC start time", () => {
  assert.equal(activityFilename(1072915200), "2023-12-31_00-00-00.fit");
});
