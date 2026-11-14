// Byte helpers shared by the companion transports: the iGPSPORT download
// (lib/igpsport/native_link.js) and the shared-file transfer
// (lib/shared_files.js) both decode base64 chunks and join them in order.

export function decodeBase64(text) {
  const binary = atob(text);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
  return bytes;
}

export function concat(parts) {
  const total = parts.reduce((sum, part) => sum + (part?.length ?? 0), 0);
  const joined = new Uint8Array(total);
  let offset = 0;
  for (const part of parts) {
    if (!part) continue;
    joined.set(part, offset);
    offset += part.length;
  }
  return joined;
}
