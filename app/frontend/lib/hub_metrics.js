// Shared metric conversion and formatting for the personal-hub charts. Values
// travel as raw SI (metres, seconds, counts); every display decision — unit
// system, locale, rounding — happens here so the tile charts, the sport mix
// and any later chart agree on how a value reads.

const METRES_PER_KILOMETRE = 1000.0
const METRES_PER_MILE = 1609.344
const METRES_PER_FOOT = 0.3048
const SECONDS_PER_HOUR = 3600

export const MIX_METRICS = ["duration", "distance", "workouts"]

export function metricUnit(metric, unitSystem) {
  const imperial = unitSystem === "imperial"
  switch (metric) {
    case "distance": return imperial ? "mi" : "km"
    case "ascent": return imperial ? "ft" : "m"
    case "duration": return "h"
    default: return ""
  }
}

export function metricDisplayValue(metric, value, unitSystem) {
  const imperial = unitSystem === "imperial"
  switch (metric) {
    case "distance": return value / (imperial ? METRES_PER_MILE : METRES_PER_KILOMETRE)
    case "ascent": return imperial ? value / METRES_PER_FOOT : value
    case "duration": return value / SECONDS_PER_HOUR
    default: return value
  }
}

function formatNumber(value, locale) {
  const rounded = Math.round(Number(value) * 10) / 10
  return new Intl.NumberFormat(locale, { maximumFractionDigits: 1 }).format(rounded)
}

export function formatMetricValue(metric, rawValue, unitSystem, locale) {
  const display = metricDisplayValue(metric, rawValue, unitSystem)
  const unit = metricUnit(metric, unitSystem)
  return `${formatNumber(display, locale)}${unit ? ` ${unit}` : ""}`
}

export function formatPercentage(value, total, locale) {
  if (!total) return "—"

  return `${formatNumber((value / total) * 100, locale)} %`
}

// Linear RGB mix of two computed colours: `ratio` is the amount of `from`
// (0..1). The sport-mix donut uses it to build a monochrome ramp of the brand
// primary, so every slice is a nuance of the same hue instead of an invented
// palette.
export function mixColors(from, to, ratio) {
  const parse = (color) => {
    const text = (color || "").trim()
    const rgb = /rgba?\(([^)]+)\)/.exec(text)
    if (rgb) {
      const [ r, g, b ] = rgb[1].split(",").map((part) => parseFloat(part))
      return { r, g, b }
    }
    const hex = /^#([0-9a-f]{6})$/i.exec(text)
    if (hex) {
      const value = parseInt(hex[1], 16)
      return { r: (value >> 16) & 255, g: (value >> 8) & 255, b: value & 255 }
    }
    return null
  }
  const start = parse(from)
  const end = parse(to)
  if (!start || !end) return from

  const blend = (a, b) => Math.round(b + (a - b) * ratio)
  return `rgb(${blend(start.r, end.r)}, ${blend(start.g, end.g)}, ${blend(start.b, end.b)})`
}
