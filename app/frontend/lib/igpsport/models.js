// The iGPSPORT computers the device source offers (docs/dev/IMPORT-SOURCES.md
// §4). Chrome's chooser filters by name prefix only, so the chosen name is
// matched again against the family's names. Only the BSC500 and the BSC100S
// are verified on hardware; every other model gets the 20-byte writes that fit
// any MTU, because Web Bluetooth exposes none.
export const NAME_PREFIXES = [
  "BSC100", "BSC200", "BSC300", "BSC500", "iGS630", "iGS800", "BiNavi", "iGPSPORT",
];

const FAMILY = [
  /^BSC(?:100|200|300|500)/,
  /^iGS(?:630|800)/,
  /^BiNavi/,
  // Gadgetbridge's BiNavi Air pattern, which tolerates a vendor prefix.
  /^(?:iGPSPORT\s*)?BiNavi[\s_-]*Air$/i,
];

const VERIFIED = new Map([
  ["BSC500", { writeSize: 244 }],
  ["BSC100S", { writeSize: 20 }],
]);

export const DEFAULT_WRITE_SIZE = 20;

export function resolveModel(name) {
  if (typeof name !== "string" || name === "") return null;

  const verified = VERIFIED.get(name);
  if (verified) return { name, verified: true, writeSize: verified.writeSize };
  if (!FAMILY.some((pattern) => pattern.test(name))) return null;

  return { name, verified: false, writeSize: DEFAULT_WRITE_SIZE };
}
