import { Controller } from "@hotwired/stimulus"
import { cssColor } from "../lib/css_color"
import { formatNumber } from "../lib/number_format"
import { loadECharts } from "../lib/charts/echarts"
import { mountChart } from "../lib/charts/lifecycle"
import { chartFont, prefersReducedMotion } from "../lib/charts/theme"
import { tooltipBase } from "../lib/charts/tooltip"

const CHART_HEIGHT = 280
const NARROW_WIDTH = 576

const escapeHtml = (value) => String(value ?? "").replace(/[&<>"']/g, (character) => `&#${character.charCodeAt(0)};`)

// Time in each heart-rate zone per week or month (PLAN_HEART_RATE.md §4):
// stacked bars in hours, or in shares of each period when the scale is
// `share` (the intensity distribution, whatever the volume), Z1 at the foot
// in the palest step of the primary ramp (DESIGN.md §10.21). The payload is embedded; the table below the chart
// is its text equivalent.
export default class extends Controller {
  static values = { payload: Object }
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
    const periods = this.payloadValue.periods || []
    const zones = this.payloadValue.zones || []
    const muted = cssColor("--allure-text-muted")
    const border = cssColor("--allure-border")
    const surface = cssColor("--allure-surface")
    const share = this.payloadValue.scale === "share"

    return {
      animation: !prefersReducedMotion(),
      animationDuration: 300,
      textStyle: { fontFamily: chartFont() },
      grid: { left: 8, right: 8, top: 32, bottom: 8, outerBoundsMode: "same", outerBoundsContain: "axisLabel" },
      // A phone-wide chart names the zones by number (« Z1 »), so the legend
      // stays on one line; the tooltip and the table keep the full names.
      legend: {
        top: 0,
        left: 0,
        icon: "roundRect",
        itemWidth: 12,
        itemHeight: 8,
        textStyle: { color: muted },
        formatter: (name) => this.chartTarget.clientWidth < NARROW_WIDTH ? name.split(" · ")[0] : name
      },
      xAxis: {
        type: "category",
        data: periods.map((period) => period.axis || period.label),
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: { color: muted, hideOverlap: true }
      },
      yAxis: {
        type: "value",
        minInterval: share ? 10 : 0.5,
        max: share ? 100 : undefined,
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: {
          color: muted,
          formatter: (value) => share
            ? `${formatNumber(value, 0)} %`
            : `${formatNumber(value, Number.isInteger(value) ? 0 : 1)} h`
        },
        splitLine: { lineStyle: { color: border, type: [4, 4] } }
      },
      tooltip: tooltipBase({
        trigger: "axis",
        axisPointer: { type: "shadow" },
        formatter: (params) => this.#tooltip(periods[params[0]?.dataIndex], zones, share)
      }),
      series: zones.map((name, index) => ({
        name,
        type: "bar",
        stack: "zones",
        barMaxWidth: 32,
        data: periods.map((period) => {
          if (!(period.seconds[index] > 0)) return null
          return share ? period.shares[index] : period.seconds[index] / 3600
        }),
        itemStyle: { color: cssColor(`--allure-zone-${index + 1}`), borderColor: surface, borderWidth: 0.5 },
        emphasis: { focus: "series" }
      }))
    }
  }

  #tooltip(period, zones, share) {
    if (!period) return ""

    const value = (index) => share
      ? `${period.time[index]} · ${formatNumber(Math.round(period.shares[index]), 0)} %`
      : period.time[index]
    const rows = zones.map((name, index) => period.seconds[index] > 0
      ? `<div><span class="hub-chart-tooltip-detail">${escapeHtml(name)}</span> ${escapeHtml(value(index))}</div>`
      : "").join("")
    return `<div class="hub-chart-tooltip"><div class="hub-chart-tooltip-title">${escapeHtml(period.label)}</div>${rows}</div>`
  }
}
