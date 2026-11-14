import { cssColor } from "../css_color";

// Chart colours come from the page's Tabler tokens, resolved for the active
// theme each time a chart is built or the theme changes
// (`allure:theme-changed`). The series palette is the one Tabler's chart
// layer defined: primary first, then green, azure, purple and orange.
const PALETTE = [
  ["--primary", "#066fd1"],
  ["--green", "#2fb344"],
  ["--azure", "#4299e1"],
  ["--purple", "#ae3ec9"],
  ["--orange", "#f76707"],
];

export function chartColors() {
  return {
    primary: cssColor("--primary", "#066fd1"),
    secondary: cssColor("--secondary", "#6c7a91"),
    text: cssColor("--body-color", "#182433"),
    border: cssColor("--border-color", "#dce1e7"),
    surface: cssColor("--bg-surface", "#ffffff"),
    palette: PALETTE.map(([variable, fallback]) => cssColor(variable, fallback)),
  };
}

// ECharts measures its labels on a canvas, where `inherit` means nothing: the
// page's real font stack must be named, or the layout reserves room for a
// narrower fallback face and the SVG text overflows it.
export const chartFont = () => getComputedStyle(document.body).fontFamily;

// The same colour at a given opacity, for gradients and translucent fills.
// Takes the `#rrggbb` or `rgb()/rgba()` values `cssColor` returns.
export function withAlpha(color, alpha) {
  const hex = /^#([0-9a-f]{6})$/i.exec(color || "");
  if (hex) {
    const value = parseInt(hex[1], 16);
    return `rgba(${(value >> 16) & 255}, ${(value >> 8) & 255}, ${value & 255}, ${alpha})`;
  }
  const rgb = /rgba?\(([^)]+)\)/.exec(color || "");
  if (rgb) {
    const [red, green, blue] = rgb[1].split(",").map((part) => parseFloat(part));
    return `rgba(${red}, ${green}, ${blue}, ${alpha})`;
  }
  return color;
}

export const prefersReducedMotion = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches;

// Dates on time axes and in tooltips follow the page language (or the locale
// a view hands over), through the platform's own calendar names: no chart
// locale to ship or keep in sync.
export function dateFormatter(options, locale = document.documentElement.lang) {
  const format = new Intl.DateTimeFormat(locale || undefined, options);
  return (value) => format.format(new Date(value));
}

// Time-axis tick labels at the precision the tick itself carries: a year on
// 1 January, a month on the 1st, a day otherwise. ECharts places its time
// ticks in local time on those boundaries.
export function timeAxisFormatter(locale) {
  const year = dateFormatter({ year: "numeric" }, locale);
  const month = dateFormatter({ month: "short", year: "numeric" }, locale);
  const day = dateFormatter({ day: "numeric", month: "short" }, locale);
  return (value) => {
    const date = new Date(value);
    if (date.getDate() !== 1) return day(value);
    return date.getMonth() === 0 ? year(value) : month(value);
  };
}
