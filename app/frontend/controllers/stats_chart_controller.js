import { Controller } from "@hotwired/stimulus"
import { formatNumber } from "../lib/number_format"
import { loadECharts } from "../lib/charts/echarts"
import { mountChart } from "../lib/charts/lifecycle"
import { chartColors, chartFont, dateFormatter, timeAxisFormatter } from "../lib/charts/theme"
import { tooltipBase } from "../lib/charts/tooltip"

const METRES_PER_KILOMETRE = 1000.0
const METRES_PER_MILE = 1609.344
const LINE_HEIGHT = 300
// The per-sport bars are horizontal (DESIGN.md §15.1): the chart grows with
// the number of sports so a bar never gets squeezed.
const BAR_ROW = 32
const BAR_MIN_HEIGHT = 160
const BAR_CHROME = 48

// One decimal at most, in the page's locale.
const formatAxis = (value) => {
  const rounded = Math.round(Number(value) * 10) / 10
  return formatNumber(rounded, Number.isInteger(rounded) ? 0 : 1)
}

// "2026-10-01" is a calendar day: read it in the reader's zone, never as UTC
// midnight, which would show the previous day west of Greenwich.
const localDay = (value) => {
  const [year, month, day] = String(value).slice(0, 10).split("-").map(Number)
  return new Date(year, month - 1, day || 1).getTime()
}

const escapeHtml = (value) => String(value).replace(/[&<>"']/g, (character) => `&#${character.charCodeAt(0)};`)

// Distance charts for the stats pages. Fetches the page's own JSON dataset
// (same endpoint, `format: :json`) and renders either a time area chart
// split by sport (by_time) or a horizontal per-sport bar chart (by_sport,
// granularity "sport"). ECharts loads on demand; teardown aborts the fetch
// and disposes the chart for Turbo safety.
export default class extends Controller {
  static values = {
    url: String,
    granularity: String,
    sports: Object,
    unitSystem: String,
    distanceLabel: String,
    unitLabel: String,
    locale: { type: String, default: "en" }
  }
  static targets = ["container", "loading", "empty", "error"]

  connect() {
    this.connected = true
    this.abortController = new AbortController()
    this.mounted = null
    this.rows = null
    this.themeChanged = () => this.#rerender()
    window.addEventListener("allure:theme-changed", this.themeChanged)
    this.#showState("loading")
    this.#load()
  }

  disconnect() {
    this.connected = false
    window.removeEventListener("allure:theme-changed", this.themeChanged)
    this.abortController?.abort()
    this.mounted?.release()
    this.mounted = null
    this.abortController = null
    this.rows = null
  }

  async #load() {
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "application/json" },
        signal: this.abortController.signal
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const data = await response.json()
      const rows = this.granularityValue === "sport" ? data.sports || [] : data.buckets || []
      if (!rows.length) return this.#showState("empty")
      this.rows = rows
      await this.#render()
      if (!this.connected) return
      this.#showState("ready")
    } catch (error) {
      if (error?.name === "AbortError") return
      if (this.connected) this.#showState("error")
    }
  }

  async #rerender() {
    if (!this.rows || !this.mounted) return
    try {
      await this.#render()
    } catch {
      if (this.connected) this.#showState("error")
    }
  }

  async #render() {
    const echarts = await loadECharts()
    if (!this.connected) return

    const divisor = this.unitSystemValue === "imperial" ? METRES_PER_MILE : METRES_PER_KILOMETRE
    const bars = this.granularityValue === "sport"
    const height = bars ? this.#barHeight() : LINE_HEIGHT
    const options = bars ? this.#barOptions(divisor) : this.#lineOptions(divisor)

    this.mounted?.release()
    this.mounted = mountChart(echarts, this.containerTarget, { height })
    this.mounted.chart.setOption(options)
  }

  #barHeight() {
    return Math.max(BAR_MIN_HEIGHT, this.rows.length * BAR_ROW + BAR_CHROME)
  }

  #sportName(sportId) {
    return this.sportsValue[sportId] || `#${sportId}`
  }

  #axis(colors) {
    return {
      axisLine: { lineStyle: { color: colors.border } },
      axisTick: { show: false },
      axisLabel: { color: colors.secondary },
      splitLine: { lineStyle: { color: colors.border, type: "dashed" } }
    }
  }

  #barOptions(divisor) {
    const colors = chartColors()
    const axis = this.#axis(colors)
    const unit = this.unitLabelValue
    return {
      animation: false,
      color: colors.palette,
      textStyle: { fontFamily: chartFont() },
      grid: { left: 8, right: 8, top: 8, bottom: 8, outerBoundsMode: "same", outerBoundsContain: "all" },
      xAxis: {
        type: "value",
        name: unit,
        nameLocation: "end",
        nameTextStyle: { color: colors.secondary },
        ...axis,
        axisLabel: { ...axis.axisLabel, formatter: formatAxis }
      },
      yAxis: {
        type: "category",
        inverse: true,
        data: this.rows.map((row) => this.#sportName(row.sport_id)),
        ...axis,
        splitLine: { show: false },
        axisLabel: { ...axis.axisLabel, color: colors.text, width: 140, overflow: "truncate" }
      },
      tooltip: tooltipBase({
        trigger: "axis",
        axisPointer: { type: "shadow" },
        formatter: (params) => {
          const [point] = params
          return `<div class="hub-chart-tooltip"><div class="hub-chart-tooltip-title">${escapeHtml(point.name)}</div>` +
            `<div class="hub-chart-tooltip-detail">${formatAxis(point.value)} ${escapeHtml(unit)}</div></div>`
        }
      }),
      series: [ {
        type: "bar",
        name: this.distanceLabelValue,
        data: this.rows.map((row) => row.total_distance / divisor),
        barMaxWidth: 20,
        itemStyle: { color: colors.primary, borderRadius: [ 0, 3, 3, 0 ] }
      } ]
    }
  }

  #lineOptions(divisor) {
    const colors = chartColors()
    const axis = this.#axis(colors)
    const unit = this.unitLabelValue
    const bySport = new Map()
    for (const row of this.rows) {
      if (!bySport.has(row.sport_id)) bySport.set(row.sport_id, [])
      bySport.get(row.sport_id).push([ localDay(row.period), row.total_distance / divisor ])
    }
    const axisDate = timeAxisFormatter(this.localeValue)
    const tooltipDate = dateFormatter(this.#tooltipDateOptions(), this.localeValue)

    return {
      animation: false,
      color: colors.palette,
      textStyle: { fontFamily: chartFont() },
      grid: { left: 8, right: 16, top: 8, bottom: 8, outerBoundsMode: "same", outerBoundsContain: "all" },
      xAxis: {
        type: "time",
        ...axis,
        splitLine: { show: false },
        axisLabel: { ...axis.axisLabel, formatter: (value) => axisDate(value), hideOverlap: true }
      },
      yAxis: {
        type: "value",
        name: unit,
        nameTextStyle: { color: colors.secondary, align: "left" },
        ...axis,
        axisLine: { show: false },
        axisLabel: { ...axis.axisLabel, formatter: formatAxis }
      },
      tooltip: tooltipBase({
        trigger: "axis",
        formatter: (params) => {
          if (!params.length) return ""
          const lines = params.map((point) =>
            `<div>${point.marker}${escapeHtml(point.seriesName)} <span class="hub-chart-tooltip-detail">${formatAxis(point.value[1])} ${escapeHtml(unit)}</span></div>`)
          return `<div class="hub-chart-tooltip"><div class="hub-chart-tooltip-title">${escapeHtml(tooltipDate(params[0].value[0]))}</div>${lines.join("")}</div>`
        }
      }),
      series: [ ...bySport.entries() ].map(([ sportId, data ]) => ({
        type: "line",
        name: this.#sportName(sportId),
        data,
        smooth: true,
        // Sparse periods must not overshoot or loop back in time.
        smoothMonotone: "x",
        showSymbol: data.length === 1,
        lineStyle: { width: 2 },
        areaStyle: { opacity: 0.12 }
      }))
    }
  }

  #tooltipDateOptions() {
    switch (this.granularityValue) {
      case "year": return { year: "numeric" }
      case "month": return { month: "long", year: "numeric" }
      default: return { day: "numeric", month: "long", year: "numeric" }
    }
  }

  #showState(name) {
    for (const target of [ "loading", "empty", "error" ]) {
      this[`${target}Target`].hidden = target !== name
    }
  }
}
