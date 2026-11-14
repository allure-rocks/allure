import { concatMany, concatBytes } from "./bytes.js";
import {
  ACTIVITY_FILE_GET,
  ACTIVITY_LIST_GET,
  ACTIVITY_LIST_NUM_GET,
  SERVICE_BLE,
  SERVICE_CYCLING_DATA,
  SERVICE_DEV_VER_INFO,
  SERVICE_FACTORY,
  SERVICE_FIRMWARE,
} from "./constants.js";

export function readVarint(bytes, start) {
  let value = 0;
  let factor = 1;
  let offset = start;

  for (let count = 0; count < 10; count += 1) {
    if (offset >= bytes.length) throw new Error("Truncated protobuf varint");
    const byte = bytes[offset++];
    value += (byte & 0x7f) * factor;
    if ((byte & 0x80) === 0) return { value, offset };
    factor *= 128;
    if (!Number.isSafeInteger(value) || !Number.isSafeInteger(factor)) {
      throw new Error("Protobuf integer exceeds JavaScript's safe range");
    }
  }

  throw new Error("Invalid protobuf varint");
}

export function parseProtobuf(bytes) {
  const fields = new Map();
  let offset = 0;

  while (offset < bytes.length) {
    const key = readVarint(bytes, offset);
    offset = key.offset;
    const fieldNumber = Math.floor(key.value / 8);
    const wireType = key.value & 7;
    if (fieldNumber === 0) throw new Error("Invalid protobuf field number 0");

    let value;
    if (wireType === 0) {
      const result = readVarint(bytes, offset);
      value = result.value;
      offset = result.offset;
    } else if (wireType === 1) {
      if (offset + 8 > bytes.length) throw new Error("Truncated fixed64 field");
      value = bytes.slice(offset, offset + 8);
      offset += 8;
    } else if (wireType === 2) {
      const length = readVarint(bytes, offset);
      offset = length.offset;
      const end = offset + length.value;
      if (end > bytes.length) throw new Error("Truncated length-delimited field");
      value = bytes.slice(offset, end);
      offset = end;
    } else if (wireType === 5) {
      if (offset + 4 > bytes.length) throw new Error("Truncated fixed32 field");
      value = bytes.slice(offset, offset + 4);
      offset += 4;
    } else {
      throw new Error(`Unsupported protobuf wire type ${wireType}`);
    }

    const values = fields.get(fieldNumber) ?? [];
    values.push(value);
    fields.set(fieldNumber, values);
  }

  return fields;
}

export function firstField(fields, number) {
  return fields.get(number)?.[0] ?? null;
}

export function nestedField(fields, number) {
  const value = firstField(fields, number);
  return value instanceof Uint8Array ? parseProtobuf(value) : null;
}

export function encodeVarint(value) {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new Error(`Invalid protobuf integer ${value}`);
  }

  const bytes = [];
  do {
    let byte = value % 128;
    value = Math.floor(value / 128);
    if (value) byte |= 0x80;
    bytes.push(byte);
  } while (value);

  return Uint8Array.from(bytes);
}

export function varintField(number, value) {
  return concatBytes(encodeVarint(number * 8), encodeVarint(value));
}

export function bytesField(number, value) {
  return concatMany([encodeVarint(number * 8 + 2), encodeVarint(value.length), value]);
}

export function activityCountPayload() {
  return concatMany([
    varintField(1, SERVICE_CYCLING_DATA),
    varintField(2, ACTIVITY_LIST_NUM_GET),
  ]);
}

export function activityListPayload(start, end) {
  if (!Number.isInteger(start) || !Number.isInteger(end) || start < 0 || start > end) {
    throw new Error("Activity page requires 0 <= start <= end");
  }

  const page = concatMany([varintField(3, start), varintField(4, end)]);
  return concatMany([
    varintField(1, SERVICE_CYCLING_DATA),
    varintField(2, ACTIVITY_LIST_GET),
    bytesField(6, page),
  ]);
}

export function activityFilePayload(timestamp) {
  const flag = varintField(1, timestamp);
  return concatMany([
    varintField(1, SERVICE_CYCLING_DATA),
    varintField(2, ACTIVITY_FILE_GET),
    bytesField(3, flag),
  ]);
}

export function decodeActivityCount(payload) {
  const listing = nestedField(parseProtobuf(payload), 6);
  return {
    fileCount: listing ? firstField(listing, 1) : null,
    pageSize: listing ? firstField(listing, 2) : null,
  };
}

export function decodeActivityList(payload) {
  const fields = parseProtobuf(payload);
  const activities = [];

  for (const encoded of fields.get(3) ?? []) {
    if (!(encoded instanceof Uint8Array)) continue;

    const entry = parseProtobuf(encoded);
    const timestamp = firstField(entry, 1);
    if (!timestamp) continue;

    activities.push({
      timestamp,
      fileSize: firstField(entry, 2),
      userId: decodeOptionalString(firstField(entry, 3)),
      deviceId: decodeOptionalString(firstField(entry, 4)),
    });
  }

  return activities;
}

export function decodeFileMetadata(payload) {
  const fields = parseProtobuf(payload);
  const fileSize = firstField(fields, 1);
  if (!Number.isSafeInteger(fileSize) || fileSize < 0) {
    throw new Error("Download metadata has no valid file size");
  }

  return {
    fileSize,
    fileId: firstField(fields, 3),
    fileName: decodeOptionalString(firstField(fields, 4)),
    fileCrc32: firstField(fields, 8),
  };
}

export function decodeOptionalString(value) {
  return value instanceof Uint8Array ? new TextDecoder().decode(value) : null;
}

export function decodeBattery(payload) {
  const data = nestedField(parseProtobuf(payload), 6);
  return {
    voltage: data ? firstField(data, 1) : null,
    battery: data ? firstField(data, 2) : null,
  };
}

export function decodeSerial(payload) {
  const data = nestedField(parseProtobuf(payload), 3);
  const encoded = data ? firstField(data, 1) : null;
  return { serial: decodeOptionalString(encoded) };
}

export function initRequests() {
  return [
    { service: SERVICE_BLE, command: 1, payload: "080A1001" },
    { service: SERVICE_FIRMWARE, command: 1, payload: "08041001" },
    { service: SERVICE_FACTORY, command: 6, payload: "080B1006", decode: decodeBattery },
    { service: SERVICE_FACTORY, command: 1, payload: "080B1001", decode: decodeSerial },
    // Gadgetbridge never sends it and the import ignores its reply, so a
    // model that stays silent does not fail the handshake.
    { service: SERVICE_DEV_VER_INFO, command: 2, payload: "08111002", optional: true },
  ];
}
