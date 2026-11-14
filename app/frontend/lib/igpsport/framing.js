import { concatBytes } from "./bytes.js";
import { HEADER_SIZE, MODE_FILE_OPERATION, PACKET_RESULT } from "./constants.js";

export function crc8Maxim(bytes) {
  let crc = 0;
  for (const value of bytes) {
    let current = value;
    for (let bit = 0; bit < 8; bit += 1) {
      const mix = (crc ^ current) & 1;
      crc >>>= 1;
      if (mix) crc ^= 0x8c;
      current >>>= 1;
    }
  }
  return crc;
}

export function craftData(service, command, payload, fileOperation = false) {
  if (payload.length > 0xffff) throw new Error("Payload exceeds framing limit");

  const header = Uint8Array.from([
    0x01, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00, 0xff, 0xff,
    0x01, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
  ]);
  header[1] = service;
  header[3] = fileOperation ? MODE_FILE_OPERATION : 0xff;
  header[4] = command;
  header[7] = payload.length >>> 8;
  header[8] = payload.length & 0xff;
  header[9] = crc8Maxim(payload);
  header[19] = crc8Maxim(header.subarray(0, 19));
  return concatBytes(header, payload);
}

export function parseHeader(bytes) {
  if (bytes.length < HEADER_SIZE) throw new Error("Incomplete packet header");

  const expected = crc8Maxim(bytes.subarray(0, 19));
  if (bytes[19] !== expected) {
    throw new Error(
      `Header CRC mismatch: got 0x${bytes[19].toString(16)}, expected 0x${expected.toString(16)}`,
    );
  }

  return {
    type: bytes[0],
    service: bytes[1],
    mode: bytes[3],
    command: bytes[4],
    size: (bytes[7] << 8) | bytes[8],
    resultCode: bytes[0] === PACKET_RESULT ? bytes[7] : null,
  };
}
