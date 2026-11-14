import { Controller } from "@hotwired/stimulus"
import { cssColor } from "../lib/css_color"
import { niceScale, PACE_STEPS } from "../lib/chart_scale"
import { loadECharts } from "../lib/charts/echarts"
import { mountChart } from "../lib/charts/lifecycle"
import { chartFont, prefersReducedMotion, timeAxisFormatter } from "../lib/charts/theme"
import { tooltipBase } from "../lib/charts/tooltip"

const MEDAL_VARIABLES = { 1: "--allure-medal-gold", 2: "--allure-medal-silver", 3: "--allure-medal-bronze" }

// A trophy callout fills a square whose bottom corner sits on its point: a
// 45° leader leaves the marker and the trophy closes it. The callout rises to
// the right, to the left where the right edge would cut it, and lengthens by
// steps where another trophy or a point already sits (efforts of one outing
// stack up). Distances are along each axis, in pixels.
const LEADER_START = 5
const TROPHY_DISTANCE = 27
const LEVEL_STEP = 18
const MAX_LEVEL = 3
const TROPHY_SIZE = 18
const POINT_CLEARANCE = 6
const TROPHY_GAP = 6
const CHART_HEIGHT = 256
const GRID_TOP = 12
const POINT_SIZE = 10

// The Tabler outline trophy (the page's `ti-trophy`), drawn over a halo of the
// card surface so it reads on the gridlines and the trend.
const TROPHY_PATHS = [
  "M8 21l8 0", "M12 17l0 4", "M7 4l10 0", "M17 4v8a5 5 0 0 1 -10 0v-8",
  "M3 9a2 2 0 1 0 4 0a2 2 0 1 0 -4 0", "M17 9a2 2 0 1 0 4 0a2 2 0 1 0 -4 0"
].map((d) => `<path d="${d}"/>`).join("")

const calloutBox = (distance) => distance + TROPHY_SIZE / 2 + 2

// dx is 1 to the right, -1 to the left; distance is the trophy's centre from
// the point along each axis.
const calloutImage = (color, halo, dx, distance) => {
  const box = calloutBox(distance)
  const cornerX = dx > 0 ? 0 : box
  const along = (offset) => [cornerX + dx * offset, box - offset]
  const [x1, y1] = along(LEADER_START)
  const [x2, y2] = along(distance - TROPHY_SIZE / 2 - 2)
  const [cx, cy] = along(distance)
  const scale = TROPHY_SIZE / 24
  const trophy = `transform="translate(${cx - TROPHY_SIZE / 2} ${cy - TROPHY_SIZE / 2}) scale(${scale})"`
  const leader = `M${x1} ${y1}L${x2} ${y2}`
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${box}" height="${box}" viewBox="0 0 ${box} ${box}" fill="none" stroke-linecap="round" stroke-linejoin="round">` +
    `<path d="${leader}" stroke="${halo}" stroke-width="4"/>` +
    `<path d="${leader}" stroke="${color}" stroke-width="1.5"/>` +
    `<g ${trophy} stroke="${halo}" stroke-width="5">${TROPHY_PATHS}</g>` +
    `<g ${trophy} stroke="${color}" stroke-width="2">${TROPHY_PATHS}</g></svg>`
  return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`
}

const escapeHtml = (text) => String(text ?? "").replace(/[&<>"']/g, (char) => `&#${char.charCodeAt(0)};`)

// A duration on the clock: 4:05, 1:02:30.
const formatClock = (value) => {
  const total = Math.max(0, Math.round(Number(value)))
  const hours = Math.floor(total / 3600)
  const minutes = Math.floor((total % 3600) / 60)
  const seconds = String(total % 60).padStart(2, "0")
  return hours > 0 ? `${hours}:${String(minutes).padStart(2, "0")}:${seconds}` : `${minutes}:${seconds}`
}

// One sport's times on a course over time (DESIGN.md §15.1): one primary
// point per effort, the three best times marked by their gold, silver or
// bronze trophy on a 45° leader beside the point, and a thin grey robust trend
// (fitted server-side, dotted where it rests on too few outings), on a
// reversed time axis so a faster effort sits higher. The payload is embedded
// in the page; the chronological table in the same card is the text
// equivalent. A point opens its workout on a pointer device; on touch, a tap
// shows the tooltip and the table carries the links.
export default class extends Controller {
  static values = { payload: Object, locale: { type: String, default: "en" } }
  static targets = ["chart", "error"]

  connect() {
    this.connected = true
    this.generation = 0
    this.mounted = null
    this.canHover = window.matchMedia("(hover: hover)").matches
    this.onThemeChanged = () => this.#render()
    window.addEventListener("allure:theme-changed", this.onThemeChanged)
    this.#render()
  }

  disconnect() {
    this.connected = false
    this.generation += 1
    window.removeEventListener("allure:theme-changed", this.onThemeChanged)
    this.mounted?.release()
    this.mounted = null
  }

  async #render() {
    const generation = ++this.generation
    try {
      const echarts = await loadECharts()
      if (!this.connected || generation !== this.generation) return

      this.mounted?.release()
      this.mounted = mountChart(echarts, this.chartTarget, {
        height: CHART_HEIGHT,
        onResize: () => this.#drawCallouts()
      })
      const { chart } = this.mounted
      chart.setOption(this.#options())
      chart.on("click", { seriesName: "efforts" }, (params) => this.#open(params.data?.point))
      this.#drawCallouts()
      this.errorTarget.hidden = true
    } catch {
      if (this.connected && generation === this.generation) this.errorTarget.hidden = false
    }
  }

  #points() {
    return this.payloadValue.points || []
  }

  #options() {
    const points = this.#points()
    const trend = this.payloadValue.trend || []
    const uncertain = this.payloadValue.trend_uncertain || []
    const primary = cssColor("--primary")
    const muted = cssColor("--allure-text-muted")
    const surface = cssColor("--allure-surface")
    const border = cssColor("--allure-border")

    const times = points.map((point) => point.y)
    const scale = niceScale(Math.min(...times), Math.max(...times), 4, PACE_STEPS)

    // The trend first, so the points and trophies sit above it. Solid where
    // it is supported, dotted where it rests on too few outings (a long gap,
    // a short history); the two share their junctions. Straight segments
    // between the server's dense grid: a spline through unevenly spaced
    // values overshoots beside a long gap and can run back.
    const series = []
    for (const [data, dashed] of [[trend, false], [uncertain, true]]) {
      if (!data.length) continue
      series.push({
        name: dashed ? "trend-uncertain" : "trend",
        type: "line",
        data: data.map((point) => [point.x, point.y ?? null]),
        showSymbol: false,
        silent: true,
        tooltip: { show: false },
        lineStyle: { color: muted, width: 1.25, opacity: 0.75, type: dashed ? [3, 3] : "solid" },
        z: 1
      })
    }
    series.push({
      name: "efforts",
      type: "scatter",
      data: points.map((point) => ({ value: [point.x, point.y], point })),
      symbolSize: POINT_SIZE,
      cursor: this.canHover ? "pointer" : "default",
      itemStyle: { color: primary, borderColor: surface, borderWidth: 1, opacity: 1 },
      emphasis: { scale: 1.4 },
      z: 3
    })

    return {
      animation: !prefersReducedMotion(),
      animationDuration: 300,
      textStyle: { fontFamily: chartFont() },
      grid: { left: 8, right: 8, top: GRID_TOP, bottom: 8, outerBoundsMode: "same", outerBoundsContain: "axisLabel" },
      xAxis: {
        type: "time",
        // A little air on both sides, so the first and last points and their
        // trophies never sit on the plot's edge.
        min: (extent) => extent.min - (extent.max - extent.min) * 0.03,
        max: (extent) => extent.max + (extent.max - extent.min) * 0.03,
        axisLine: { show: false },
        axisTick: { show: false },
        splitLine: { show: false },
        axisLabel: { color: muted, hideOverlap: true, formatter: timeAxisFormatter(this.localeValue) },
        axisPointer: { show: false }
      },
      yAxis: {
        type: "value",
        inverse: true,
        min: scale.min,
        max: scale.max,
        interval: scale.step,
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: { color: muted, formatter: formatClock },
        splitLine: { lineStyle: { color: border, type: [4, 4] } }
      },
      tooltip: tooltipBase({
        trigger: "item",
        formatter: (params) => this.#tooltip(params.data?.point)
      }),
      series
    }
  }

  // Places each trophy, gold first, on the first free spot of its candidates
  // (rising right, then left, a step further each round), from the chart's
  // real pixel positions; when a trophy would leave the top of the chart, the
  // plot moves down by what it needs and the placement runs again.
  #drawCallouts() {
    const chart = this.mounted?.chart
    if (!chart || chart.isDisposed()) return

    const points = this.#points()
    let top = GRID_TOP
    chart.setOption({ grid: { top } })
    let placement = this.#place(chart, points)
    for (let pass = 0; pass < 3 && placement.headroom > 0; pass++) {
      top += placement.headroom
      chart.setOption({ grid: { top } })
      placement = this.#place(chart, points)
    }

    const surface = cssColor("--allure-surface")
    const images = {}
    const elements = placement.spots.map(({ point, at, dx, distance }) => {
      const key = `${point.place}:${dx}:${distance}`
      images[key] ||= calloutImage(cssColor(MEDAL_VARIABLES[point.place]), surface, dx, distance)
      const box = calloutBox(distance)
      return {
        type: "image",
        silent: true,
        z: 10,
        x: dx > 0 ? at.x : at.x - box,
        y: at.y - box,
        style: { image: images[key], width: box, height: box }
      }
    })
    chart.setOption({ graphic: { id: "callouts", type: "group", silent: true, children: elements } }, { replaceMerge: ["graphic"] })
  }

  #place(chart, points) {
    const width = chart.getWidth()
    const pixel = (point) => {
      const [x, y] = chart.convertToPixel({ seriesName: "efforts" }, [point.x, point.y])
      return { x, y }
    }
    const markers = points.map(pixel)
    const trophies = []
    let needed = 0

    // How far a centre stays clear of the trophies and points already there;
    // zero or more is free.
    const clearance = (centre) => Math.min(
      ...trophies.map((other) => Math.hypot(other.x - centre.x, other.y - centre.y) - (TROPHY_SIZE + TROPHY_GAP)),
      ...markers.map((marker) => Math.hypot(marker.x - centre.x, marker.y - centre.y) - (TROPHY_SIZE / 2 + POINT_CLEARANCE))
    )

    const spots = points
      .map((point, index) => ({ point, at: markers[index] }))
      .filter(({ point }) => MEDAL_VARIABLES[point.place])
      .sort((a, b) => a.point.place - b.point.place)
      .map(({ point, at }) => {
        const candidates = []
        for (let level = 0; level <= MAX_LEVEL; level++) {
          const distance = TROPHY_DISTANCE + level * LEVEL_STEP
          for (const dx of [1, -1]) {
            const centre = { x: at.x + dx * distance, y: at.y - distance }
            if (centre.x + TROPHY_SIZE / 2 > width || centre.x - TROPHY_SIZE / 2 < 0) continue
            candidates.push({ dx, distance, centre })
          }
        }
        const scored = candidates.map((candidate) => ({ ...candidate, clear: clearance(candidate.centre) }))
        const spot = scored.find(({ clear }) => clear >= 0) ||
          scored.reduce((best, candidate) => (candidate.clear > best.clear ? candidate : best), scored[0]) ||
          { dx: 1, distance: TROPHY_DISTANCE, centre: { x: at.x + TROPHY_DISTANCE, y: at.y - TROPHY_DISTANCE } }

        trophies.push(spot.centre)
        needed = Math.max(needed, Math.ceil(TROPHY_SIZE / 2 + 2 - spot.centre.y))
        return { point, at, dx: spot.dx, distance: spot.distance }
      })

    return { spots, headroom: needed }
  }

  #tooltip(point) {
    if (!point) return ""

    const facts = [point.time, point.pace].filter(Boolean).map(escapeHtml).join(" · ")
    return `<div class="hub-chart-tooltip">` +
      `<div class="hub-chart-tooltip-title">${escapeHtml(point.title)}</div>` +
      `<div class="hub-chart-tooltip-detail">${escapeHtml(point.date)}</div>` +
      `<div>${facts}</div>` +
      `<div class="hub-chart-tooltip-detail">${escapeHtml(point.gap)}</div>` +
      `</div>`
  }

  #open(point) {
    if (!this.canHover) return
    if (point?.url && window.Turbo) window.Turbo.visit(point.url)
  }
}
