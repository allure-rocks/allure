import { toHex } from "./bytes.js";
import { GARMIN_EPOCH_MS } from "./constants.js";

const CRC32_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let index = 0; index < table.length; index += 1) {
    let value = index;
    for (let bit = 0; bit < 8; bit += 1) {
      value = (value >>> 1) ^ ((value & 1) ? 0xedb88320 : 0);
    }
    table[index] = value >>> 0;
  }
  return table;
})();

const FIT_CRC_TABLE = [
  0x0000, 0xcc01, 0xd801, 0x1400, 0xf001, 0x3c00, 0x2800, 0xe401,
  0xa001, 0x6c00, 0x7800, 0xb401, 0x5000, 0x9c01, 0x8801, 0x4400,
];

export function crc32(bytes) {
  let value = 0xffffffff;
  for (const byte of bytes) {
    value = (value >>> 8) ^ CRC32_TABLE[(value ^ byte) & 0xff];
  }
  return (value ^ 0xffffffff) >>> 0;
}

export function fitCrc16(bytes) {
  let crc = 0;
  for (const byte of bytes) {
    let checksum = FIT_CRC_TABLE[crc & 0x0f];
    crc = ((crc >>> 4) & 0x0fff) ^ checksum ^ FIT_CRC_TABLE[byte & 0x0f];
    checksum = FIT_CRC_TABLE[crc & 0x0f];
    crc = ((crc >>> 4) & 0x0fff) ^ checksum ^ FIT_CRC_TABLE[(byte >>> 4) & 0x0f];
  }
  return crc;
}

export function validateFit(content, metadata) {
  const errors = [];
  if (content.length !== metadata.fileSize) {
    errors.push(`metadata declares ${metadata.fileSize} bytes, received ${content.length}`);
  }
  if (content.length < 12) return { ok: false, errors: [...errors, "file is too short"] };

  const headerSize = content[0];
  if (![12, 14].includes(headerSize)) errors.push(`unexpected FIT header size ${headerSize}`);
  if (toHex(content.slice(8, 12)) !== "2E464954") errors.push("missing .FIT signature");

  if ([12, 14].includes(headerSize)) {
    const view = new DataView(content.buffer, content.byteOffset, content.byteLength);
    const expectedSize = headerSize + view.getUint32(4, true) + 2;
    if (content.length !== expectedSize) errors.push(`FIT header declares ${expectedSize} bytes`);
    if (headerSize === 14 && content.length >= 14) {
      const storedHeaderCrc = view.getUint16(12, true);
      if (storedHeaderCrc && fitCrc16(content.slice(0, 12)) !== storedHeaderCrc) {
        errors.push("FIT header CRC mismatch");
      }
    }
  }

  if (content.length >= 2) {
    const stored = content[content.length - 2] | (content[content.length - 1] << 8);
    if (fitCrc16(content.slice(0, -2)) !== stored) errors.push("FIT file CRC mismatch");
  }
  if (metadata.fileCrc32 !== null && metadata.fileCrc32 !== undefined && crc32(content) !== metadata.fileCrc32) {
    errors.push("device CRC32 mismatch");
  }

  return { ok: errors.length === 0, errors };
}

export function activityDate(timestamp) {
  return new Date(GARMIN_EPOCH_MS + timestamp * 1000);
}

export function activityFilename(timestamp) {
  return `${activityDate(timestamp).toISOString().replace("T", "_").replaceAll(":", "-").slice(0, 19)}.fit`;
}
