// Third-party chart and map libraries accept concrete colours, not CSS custom
// properties. Resolving through an attached element also evaluates Tabler's
// light-dark() values for the active theme.
//
// Tabler 1.6 defines its palette in oklch() and color-mix(), and the browser
// keeps that colour space in the computed value. MapLibre rejects such a value
// outright, and our own colour parsers (contrast ratios, hub tints) only read
// sRGB, so every resolved colour is normalized through a 1×1 canvas — the one
// browser API that converts any CSS colour space to 8-bit sRGB.
//
// `within` resolves the token inside an element instead of the body: a map
// carries its own `data-bs-theme` (its basemap variant), which may differ
// from the page's.
let context;

export function cssColor(variable, fallback, { within } = {}) {
  const probe = document.createElement("span");
  probe.style.color = `var(${variable}, ${fallback})`;
  (within || document.body).append(probe);
  const color = getComputedStyle(probe).color;
  probe.remove();
  return normalize(color) || color || fallback;
}

const INVALID_PROBE = "#010203";

function normalize(color) {
  context ||= document.createElement("canvas").getContext("2d", { willReadFrequently: true });
  if (!context) return null;

  context.fillStyle = INVALID_PROBE;
  context.fillStyle = color;
  if (context.fillStyle === INVALID_PROBE) return null;

  context.clearRect(0, 0, 1, 1);
  context.fillRect(0, 0, 1, 1);
  const [red, green, blue, alpha] = context.getImageData(0, 0, 1, 1).data;
  if (alpha === 255) return rgbToHex(red, green, blue);
  return `rgba(${red}, ${green}, ${blue}, ${(alpha / 255).toFixed(3)})`;
}

function rgbToHex(red, green, blue) {
  return `#${[red, green, blue].map((channel) => channel.toString(16).padStart(2, "0")).join("")}`;
}
