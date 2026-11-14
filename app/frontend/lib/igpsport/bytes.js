export function bytesFromHex(hex) {
  if (hex.length % 2 !== 0 || !/^[0-9a-f]*$/i.test(hex)) {
    throw new Error("Invalid hexadecimal string");
  }

  return Uint8Array.from(hex.match(/../g) ?? [], (pair) => Number.parseInt(pair, 16));
}

export function toHex(bytes) {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("").toUpperCase();
}

export function concatBytes(left, right) {
  const joined = new Uint8Array(left.length + right.length);
  joined.set(left);
  joined.set(right, left.length);
  return joined;
}

export function concatMany(parts) {
  return parts.reduce((result, part) => concatBytes(result, part), new Uint8Array());
}
