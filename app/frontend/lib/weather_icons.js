// The weather icons of the profile and map markers (PLAN_WEATHER.md §7): Bas
// Milius' Meteocons (MIT — see app/views/weather/icons/LICENSE), monochrome
// in `currentColor`. The server owns the files and hands each marker both
// variants as `svg: { animated, static }`; nothing here reads a file, so the
// icons stay out of the bundle.
import { prefersReducedMotion } from "./charts/theme";

// The animated icon, or the static one when the reader asked for less motion
// (DESIGN.md §16, checked when the caller draws).
export function weatherIconMarkup(svg) {
  if (!svg) return undefined;
  return prefersReducedMotion() ? (svg.static ?? svg.animated) : (svg.animated ?? svg.static);
}

// An image never inherits the page's colour, so the ink is written in.
function inked(markup, color) {
  return markup.replaceAll("currentColor", color);
}

// A `data:` URL for an `<img>`. Several copies of the same icon stay
// independent that way, where inlined markup would repeat its ids.
export function weatherIconUrl(svg, { color = "#ffffff" } = {}) {
  const markup = weatherIconMarkup(svg);
  return markup === undefined ? undefined : `data:image/svg+xml;charset=utf-8,${encodeURIComponent(inked(markup, color))}`;
}

// The weather pill of the profile chart (PLAN_WEATHER.md §7): the icon, in
// the given ink, inside a round surface ringed like the other markers,
// composed here because ECharts draws a symbol as one image. The theme's
// colours arrive as arguments, so a theme change recomposes.
export function weatherPillUrl(svg, { background, border, color = "#ffffff", size = 36, iconRatio = 0.62 } = {}) {
  const markup = weatherIconMarkup(svg);
  if (markup === undefined) return undefined;

  // The icon stays a nested <svg>, so its root attributes (`fill="none"`
  // among them) still apply to its drawing.
  const iconSize = size * iconRatio;
  const offset = (size - iconSize) / 2;
  const icon = inked(markup, color).trim().replace(/^<svg /, `<svg x="${offset}" y="${offset}" width="${iconSize}" height="${iconSize}" `);
  const svgMarkup =
    `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">` +
    `<circle cx="${size / 2}" cy="${size / 2}" r="${size / 2 - 1}" fill="${background}" stroke="${border}" stroke-width="2"/>` +
    `${icon}</svg>`;

  return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svgMarkup)}`;
}
