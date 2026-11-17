import { Controller } from "@hotwired/stimulus"
import { cssColor } from "../lib/css_color"
import { formatNumber } from "../lib/number_format"
import { loadECharts } from "../lib/charts/echarts"
import { mountChart } from "../lib/charts/lifecycle"
import { chartFont, prefersReducedMotion, timeAxisFormatter, withAlpha } from "../lib/charts/theme"
import { tooltipBase } from "../lib/charts/tooltip"

const CHART_HEIGHT = 240

const escapeHtml = (value) => String(value ?? "").replace(/[&<>"']/g, (character) => `&#${character.charCodeAt(0)};`)

// "2026-10-01" is a calendar day: read it in the reader's zone, never as UTC
// midnight.
const localDay = (value) => {
  const [year, month, day] = String(value).slice(0, 10).split("-").map(Number)
  return new Date(year, month - 1, day).getTime()
}

const signed = (value) => {
  const rounded = Math.round(Number(value))
  if (rounded > 0) return `+${formatNumber(rounded, 0)}`
  return rounded < 0 ? `−${formatNumber(-rounded, 0)}` : "0"
}

// Training load over 90 days (docs/dev/HEART-RATE.md, DESIGN.md §15.1):
// fitness as a primary area, fatigue as a muted line, form as thin bars around
// zero on the same axis, and the first six weeks of the history shaded. The
// payload is embedded in the card; its weekly table is the text equivalent.
export default class extends Controller {
  static values = { payload: Object, locale: { type: String, default: "en" } }
  static targets = ["chart", "error"]

  connect() {
    this.connected = true
    this.generation = 0
    this.mounted = null
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
      this.mounted = mountChart(echarts, this.chartTarget, { height: CHART_HEIGHT })
      this.mounted.chart.setOption(this.#options())
      this.errorTarget.hidden = true
    } catch {
      if (this.connected && generation === this.generation) this.errorTarget.hidden = false
    }
  }

  #options() {
    const points = this.payloadValue.points || []
    const names = this.payloadValue.series || {}
    const primary = cssColor("--primary")
    const muted = cssColor("--allure-text-muted")
    const border = cssColor("--allure-border")
    const at = (key) => points.map((point) => [localDay(point.x), point[key]])

    return {
      animation: !prefersReducedMotion(),
      animationDuration: 300,
      textStyle: { fontFamily: chartFont() },
      grid: { left: 8, right: 8, top: 28, bottom: 8, outerBoundsMode: "same", outerBoundsContain: "axisLabel" },
      legend: {
        top: 0,
        left: 0,
        icon: "roundRect",
        itemWidth: 12,
        itemHeight: 8,
        textStyle: { color: muted },
        data: [names.fitness, names.fatigue, names.form]
      },
      xAxis: {
        type: "time",
        splitNumber: 6,
        axisLine: { show: false },
        axisTick: { show: false },
        splitLine: { show: false },
        axisLabel: { color: muted, hideOverlap: true, formatter: timeAxisFormatter(this.localeValue) }
      },
      yAxis: {
        type: "value",
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: { color: muted, formatter: (value) => formatNumber(value, 0) },
        splitLine: { lineStyle: { color: border, type: [4, 4] } }
      },
      tooltip: tooltipBase({
        trigger: "axis",
        axisPointer: { type: "line", lineStyle: { color: muted } },
        formatter: (params) => this.#tooltip(points[params[0]?.dataIndex])
      }),
      series: [
        {
          name: names.form,
          type: "bar",
          data: at("form"),
          barWidth: "60%",
          itemStyle: { color: withAlpha(muted, 0.35) },
          z: 1
        },
        {
          name: names.fitness,
          type: "line",
          data: at("fitness"),
          showSymbol: false,
          lineStyle: { color: primary, width: 2 },
          itemStyle: { color: primary },
          areaStyle: { color: withAlpha(primary, 0.15) },
          markArea: this.#warmupArea(points, muted),
          z: 3
        },
        {
          name: names.fatigue,
          type: "line",
          data: at("fatigue"),
          showSymbol: false,
          lineStyle: { color: muted, width: 1.25 },
          itemStyle: { color: muted },
          z: 2
        }
      ]
    }
  }

  // The first six weeks of the history, where both averages still climb from
  // zero: shaded so the rise is not read as fitness gained.
  #warmupArea(points, muted) {
    const until = this.payloadValue.warmup_until
    if (!until || points.length === 0) return undefined

    return {
      silent: true,
      itemStyle: { color: withAlpha(muted, 0.1) },
      data: [[{ xAxis: localDay(points[0].x) }, { xAxis: localDay(until) }]]
    }
  }

  #tooltip(point) {
    if (!point) return ""

    const names = this.payloadValue.series || {}
    const row = (name, value) =>
      `<div><span class="hub-chart-tooltip-detail">${escapeHtml(name)}</span> ${escapeHtml(value)}</div>`
    return `<div class="hub-chart-tooltip">` +
      `<div class="hub-chart-tooltip-title">${escapeHtml(point.label)}</div>` +
      row(names.load, formatNumber(point.load, 0)) +
      row(names.fitness, formatNumber(Math.round(point.fitness), 0)) +
      row(names.fatigue, formatNumber(Math.round(point.fatigue), 0)) +
      row(names.form, signed(point.form)) +
      `</div>`
  }
}
