import { Controller } from "@hotwired/stimulus"
import { cssColor } from "../lib/css_color"
import { formatMetricValue, formatPercentage, mixColors, MIX_METRICS } from "../lib/hub_metrics"
import { loadECharts } from "../lib/charts/echarts"
import { mountChart } from "../lib/charts/lifecycle"
import { chartColors, chartFont, prefersReducedMotion } from "../lib/charts/theme"
import { tooltipBase } from "../lib/charts/tooltip"

const RAMP_END = 0.8
const HEIGHT = 260
const PHONE_HEIGHT = 170

const escapeHtml = (text) => String(text).replace(/[&<>"']/g, (char) => `&#${char.charCodeAt(0)};`)

// The sport mix of the personal hub (DESIGN.md §15.1): a donut of the sports
// practiced in the period, one slice per sport, in a monochrome ramp of the
// brand primary, with the legend at its side and a meaningful total (or the
// selected slice's formatted value) in the centre. The metric selector
// (distance, duration, activity count) re-renders from the embedded payload
// without refetching; the server-rendered tables are the chart's equivalent.
//
// Selecting is the same for every input (§15.1): tapping or clicking a slice
// or its legend entry selects that sport — the centre then names it — and the
// panel below offers the button that filters the hub to it. The legend is
// our own list of buttons, so it is reachable from the keyboard; it never
// hides a series, and nothing on the chart navigates by itself.
export default class extends Controller {
  static values = { payload: Object, metric: { type: String, default: "duration" } }
  static targets = ["container", "chart", "legend", "empty", "metric", "table", "detail", "detailText", "open"]

  connect() {
    this.connected = true
    this.generation = 0
    this.mounted = null
    this.entries = []
    this.selectedName = null
    this.canHover = window.matchMedia("(hover: hover)").matches
    this.activeMetric = this.hasMetricTarget
      ? (this.metricTargets.find((control) => control.type === "radio" && control.checked)?.value || this.metricValue)
      : this.metricValue
    this.activeMetric = MIX_METRICS.includes(this.activeMetric) ? this.activeMetric : "duration"
    this.phone = window.matchMedia("(max-width: 575.98px)")
    this.onBreakpoint = () => this.mounted?.chart.resize({ height: this.#height() })
    this.phone.addEventListener("change", this.onBreakpoint)
    this.onThemeChanged = () => this.#render()
    window.addEventListener("allure:theme-changed", this.onThemeChanged)
    this.#updateTables()
    this.#render()
  }

  disconnect() {
    this.connected = false
    this.generation += 1
    window.removeEventListener("allure:theme-changed", this.onThemeChanged)
    this.phone.removeEventListener("change", this.onBreakpoint)
    this.mounted?.release()
    this.mounted = null
  }

  selectMetric(event) {
    const metric = event.target.value
    if (!MIX_METRICS.includes(metric) || metric === this.activeMetric) return

    this.activeMetric = metric
    this.#syncMetricControls()
    this.#updateTables()
    this.#render()
  }

  clear() {
    this.selectedName = null
    this.#applySelection()
  }

  legendSelect(event) {
    this.#toggle(Number(event.currentTarget.dataset.index))
  }

  legendEnter(event) {
    this.#highlight("highlight", Number(event.currentTarget.dataset.index))
  }

  legendLeave(event) {
    this.#highlight("downplay", Number(event.currentTarget.dataset.index))
  }

  #highlight(type, dataIndex) {
    if (Number.isInteger(dataIndex)) this.mounted?.chart.dispatchAction({ type, seriesIndex: 0, dataIndex })
  }

  #toggle(index) {
    const entry = this.entries[index]
    if (!entry) return

    this.selectedName = entry.name === this.selectedName ? null : entry.name
    this.#applySelection()
  }

  #selectedEntry() {
    return this.entries.find((entry) => entry.name === this.selectedName) || null
  }

  // The centre names the selected sport (or the total), the legend marks it,
  // and the panel carries its value, share and filter button; "Others" has no
  // sport to filter on.
  #applySelection() {
    if (!this.connected) return

    const entry = this.#selectedEntry()
    if (!entry) this.selectedName = null
    this.mounted?.chart.setOption({ graphic: this.#centre() })
    if (this.hasLegendTarget) {
      for (const button of this.legendTarget.querySelectorAll("button")) {
        button.setAttribute("aria-pressed", String(this.entries[Number(button.dataset.index)]?.name === this.selectedName))
      }
    }
    if (!this.hasDetailTarget) return

    this.detailTarget.hidden = !entry
    if (!entry) return

    const payload = this.payloadValue
    const total = this.#total()
    const name = document.createElement("strong")
    name.className = "text-body"
    name.textContent = entry.name
    const facts = document.createElement("span")
    facts.className = "text-secondary"
    facts.textContent = ` · ${formatMetricValue(this.activeMetric, entry.value, payload.unit_system, payload.locale)} · ${formatPercentage(entry.value, total, payload.locale)}`
    this.detailTextTarget.replaceChildren(name, facts)

    if (this.hasOpenTarget) {
      this.openTarget.hidden = !entry.url
      if (entry.url) {
        this.openTarget.href = entry.url
        this.openTarget.textContent = entry.openLabel
      }
    }
  }

  #total() {
    return this.entries.reduce((sum, item) => sum + item.value, 0)
  }

  #centre() {
    const payload = this.payloadValue
    const entry = this.#selectedEntry()
    const colors = this.colors || chartColors()
    const value = formatMetricValue(this.activeMetric, entry ? entry.value : this.#total(), payload.unit_system, payload.locale)
    return [ {
      id: "centre",
      type: "text",
      left: "center",
      top: "middle",
      silent: true,
      style: {
        text: `{name|${entry ? entry.name : payload.total_label}}\n{value|${value}}`,
        align: "center",
        fontFamily: chartFont(),
        rich: {
          name: { fontSize: 13, lineHeight: 20, fill: colors.secondary, align: "center" },
          value: { fontSize: 16, lineHeight: 22, fontWeight: 600, fill: colors.text, align: "center" }
        }
      }
    } ]
  }

  // The segmented radios (md and up) and the native select (phones) drive the
  // same metric; whichever changed, the other follows.
  #syncMetricControls() {
    this.metricTargets.forEach((control) => {
      if (control.type === "radio") control.checked = control.value === this.activeMetric
      else control.value = this.activeMetric
    })
  }

  #height() {
    return this.phone.matches ? PHONE_HEIGHT : HEIGHT
  }

  async #render() {
    const entries = this.#entries()
    this.entries = entries
    if (!entries.length) {
      this.clear()
      return this.#showState("empty")
    }

    const generation = ++this.generation

    try {
      const echarts = await loadECharts()
      if (!this.connected || generation !== this.generation) return

      this.#showState("ready")
      this.#renderLegend()
      this.mounted?.release()
      this.mounted = mountChart(echarts, this.chartTarget, { height: this.#height() })
      const { chart } = this.mounted
      chart.setOption(this.#options())
      chart.on("click", (params) => this.#toggle(params.dataIndex))
      // A metric change keeps the selected sport when it still has a slice.
      this.#applySelection()
    } catch {
      if (this.connected && generation === this.generation) this.#showState("empty")
    }
  }

  // One nuance of the brand primary per visible slice, strongest first, so
  // the ramp always starts on the leading sport and ends on the lightest
  // step whatever the metric filters out.
  #entries() {
    const payload = this.payloadValue
    const primary = cssColor("--primary")
    const slices = payload.slices.filter((slice) => slice.values[this.activeMetric] > 0)
    const step = slices.length > 1 ? RAMP_END / (slices.length - 1) : 0

    return slices.map((slice, position) => ({
      name: slice.name,
      value: slice.values[this.activeMetric],
      color: mixColors(primary, "#ffffff", 1 - position * step),
      url: slice.url || null,
      openLabel: slice.open_label || ""
    }))
  }

  // Each legend entry carries its share, so the legend reads as the chart's
  // own summary without opening the data table.
  #renderLegend() {
    if (!this.hasLegendTarget) return

    const payload = this.payloadValue
    const total = this.#total()
    const items = this.entries.map((entry, index) => {
      const item = document.createElement("li")
      const button = document.createElement("button")
      button.type = "button"
      button.className = "hub-mix-legend-button"
      button.dataset.index = String(index)
      button.dataset.action = "hub-pie#legendSelect mouseenter->hub-pie#legendEnter mouseleave->hub-pie#legendLeave focus->hub-pie#legendEnter blur->hub-pie#legendLeave"
      button.setAttribute("aria-pressed", "false")
      const swatch = document.createElement("span")
      swatch.className = "hub-mix-legend-swatch"
      swatch.style.backgroundColor = entry.color
      swatch.setAttribute("aria-hidden", "true")
      const name = document.createElement("span")
      name.textContent = entry.name
      const share = document.createElement("span")
      share.className = "hub-mix-legend-share"
      share.textContent = formatPercentage(entry.value, total, payload.locale)
      button.append(swatch, name, share)
      item.append(button)
      return item
    })
    this.legendTarget.replaceChildren(...items)
  }

  #options() {
    const payload = this.payloadValue
    const total = this.#total()
    this.colors = chartColors()

    return {
      animation: !prefersReducedMotion(),
      animationDuration: 300,
      textStyle: { fontFamily: chartFont() },
      tooltip: tooltipBase({
        show: this.canHover,
        trigger: "item",
        formatter: (params) => {
          const value = formatMetricValue(this.activeMetric, params.value, payload.unit_system, payload.locale)
          return `<div class="hub-chart-tooltip">${escapeHtml(params.name)} : ${value} (${formatPercentage(params.value, total, payload.locale)})</div>`
        }
      }),
      graphic: this.#centre(),
      series: [ {
        type: "pie",
        radius: [ "58%", "86%" ],
        center: [ "50%", "50%" ],
        avoidLabelOverlap: false,
        label: { show: false },
        labelLine: { show: false },
        cursor: "pointer",
        emphasis: { scaleSize: 3 },
        itemStyle: { borderColor: cssColor("--allure-surface"), borderWidth: 1 },
        data: this.entries.map((entry) => ({ name: entry.name, value: entry.value, itemStyle: { color: entry.color } }))
      } ]
    }
  }

  #updateTables() {
    for (const table of this.tableTargets) table.hidden = table.dataset.metric !== this.activeMetric
  }

  #showState(name) {
    this.containerTarget.hidden = name === "empty"
    if (this.hasEmptyTarget) this.emptyTarget.hidden = name !== "empty"
  }
}
