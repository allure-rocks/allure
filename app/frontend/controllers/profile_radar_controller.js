import { Controller } from "@hotwired/stimulus"
import { loadECharts } from "../lib/charts/echarts"
import { mountChart } from "../lib/charts/lifecycle"
import { chartColors, chartFont, withAlpha } from "../lib/charts/theme"

// One measure, with sports as axes. Radar axes are linear in ECharts, so every
// SI value uses the same zero-safe log1p transform and common maximum. Only the
// drawing is transformed: the visible maximum and table keep the real values.
export default class extends Controller {
  static values = { payload: Object }
  static targets = ["visual", "chart", "error", "data", "label", "tooltip", "tooltipName", "tooltipValue"]

  connect() {
    this.connected = true
    this.generation = (this.generation || 0) + 1
    this.#load(this.generation)
  }

  disconnect() {
    this.clear()
    this.connected = false
    this.generation += 1
    this.mounted?.release()
    this.mounted = null
    this.echarts = null
    this.points = null
    this.entries = null
    this.visualTarget.hidden = true
    this.errorTarget.hidden = true
    this.dataTarget.open = true
  }

  async #load(generation) {
    try {
      const echarts = await loadECharts()
      if (!this.connected || generation !== this.generation) return

      this.echarts = echarts
      this.visualTarget.hidden = false
      this.mounted = mountChart(echarts, this.chartTarget, { onResize: () => this.render() })
      this.render()
      this.dataTarget.open = false
    } catch {
      if (!this.connected || generation !== this.generation) return

      this.mounted?.release()
      this.mounted = null
      this.visualTarget.hidden = true
      this.errorTarget.hidden = false
      this.dataTarget.open = true
    }
  }

  render() {
    if (!this.connected || !this.mounted) return

    this.clear()
    const entries = this.payloadValue.entries.filter((entry) => Number.isFinite(entry.value) && entry.value >= 0)
    this.entries = entries
    const maximum = Math.log1p(Math.max(1, ...entries.map((entry) => entry.value)))
    const colors = chartColors()
    const common = {
      animation: false,
      textStyle: { fontFamily: chartFont() },
      tooltip: { show: false },
      aria: { enabled: false }
    }
    const values = entries.map((entry) => Math.log1p(entry.value))

    if (entries.length < 3) {
      this.mode = "bars"
      this.mounted.chart.setOption({
        ...common,
        grid: { left: 100, right: 12, top: 30, bottom: 30, outerBoundsMode: "none" },
        xAxis: { type: "value", min: 0, max: maximum, show: false },
        yAxis: {
          type: "category", inverse: true, data: entries.map((entry) => entry.name),
          axisLine: { show: false }, axisTick: { show: false },
          axisLabel: { color: colors.text, fontSize: 11, width: 88, overflow: "truncate" }
        },
        series: [{ type: "bar", silent: true, data: values, barMaxWidth: 28, itemStyle: { color: colors.primary } }]
      }, { notMerge: true })
      this.points = entries.map((entry, index) => {
        const [x, y] = this.mounted.chart.convertToPixel({ seriesIndex: 0 }, [values[index], entry.name])
        return { x, y }
      })
      return
    }

    const width = this.chartTarget.clientWidth
    const labelWidth = Math.min(76, Math.max(48, width * 0.2))
    const radius = Math.max(40, Math.min(125, (width - 2 * (labelWidth + 12)) / 2))
    this.mode = "radar"
    this.mounted.chart.setOption({
      ...common,
      radar: {
        center: ["50%", "50%"], radius, startAngle: 90, clockwise: false, shape: "polygon", splitNumber: 4,
        indicator: entries.map((entry) => ({ name: entry.name, min: 0, max: maximum })),
        axisNameGap: 8,
        axisName: {
          color: colors.text, fontSize: 11,
          // Radar axis names do not honor text-style width. Use ECharts'
          // public formatter instead of letting long names leave the card.
          formatter: (name) => this.echarts.format.truncateText(name, labelWidth, `11px ${chartFont()}`, "…")
        },
        axisLine: { lineStyle: { color: colors.border } },
        splitLine: { lineStyle: { color: colors.border } },
        splitArea: { areaStyle: { color: [withAlpha(colors.primary, 0.02), withAlpha(colors.primary, 0.05)] } }
      },
      series: [{
        type: "radar", silent: true, symbol: "circle", symbolSize: 4,
        lineStyle: { color: colors.primary, width: 2 },
        itemStyle: { color: colors.primary },
        areaStyle: { color: colors.primary, opacity: 0.18 },
        emphasis: { disabled: true },
        data: [{ value: values }]
      }]
    }, { notMerge: true })
    // Radar has no public pixel converter. Mirror only the explicit drawing
    // geometry above, never reach into the chart's coordinate-system internals.
    this.points = entries.map((_entry, index) => {
      const angle = -Math.PI / 2 - index * Math.PI * 2 / entries.length
      const distance = radius * values[index] / maximum
      const cx = width / 2, cy = this.chartTarget.clientHeight / 2
      return {
        x: cx + distance * Math.cos(angle), y: cy + distance * Math.sin(angle),
        axisX: cx + (radius + 8) * Math.cos(angle), axisY: cy + (radius + 8) * Math.sin(angle),
        distance
      }
    })
  }

  clear() {
    this.press = null
    this.activeIndex = null
    this.tooltipTarget.hidden = true
  }

  dismiss(event) {
    if (!this.visualTarget.contains(event.target)) this.clear()
  }

  pointerLeave(event) {
    if (event.pointerType === "mouse") this.clear()
  }

  pointerDown(event) {
    if (!event.isPrimary) {
      this.clear()
      return
    }
    if (event.pointerType === "mouse" || event.button !== 0) return

    this.press = { id: event.pointerId, x: event.clientX, y: event.clientY, at: performance.now() }
  }

  pointerMove(event) {
    if (event.pointerType === "mouse" && !event.buttons) {
      const index = this.#hit(event, 16)
      if (index === null) this.clear()
      else this.#show(index)
    } else if (this.press && Math.hypot(event.clientX - this.press.x, event.clientY - this.press.y) > 10) {
      this.clear()
    }
  }

  pointerUp(event) {
    const press = this.press
    this.press = null
    if (!press || press.id !== event.pointerId) return

    if (performance.now() - press.at > 400 || Math.hypot(event.clientX - press.x, event.clientY - press.y) > 10) {
      this.clear()
      return
    }
    const index = this.#hit(event, 24)
    if (index === null || (index === this.activeIndex && !this.tooltipTarget.hidden)) this.clear()
    else this.#show(index)
  }

  #hit(event, tolerance) {
    if (!this.connected || !this.points) return null

    const box = this.chartTarget.getBoundingClientRect()
    const x = event.clientX - box.left, y = event.clientY - box.top
    if (x < 0 || y < 0 || x > box.width || y > box.height) return null

    let nearest = null, best = tolerance
    this.points.forEach((point, index) => {
      // Near-centre vertices overlap; their axis ends remain unambiguous.
      const distance = this.mode === "bars" ? Math.abs(y - point.y) : Math.min(
        point.distance < 6 ? Infinity : Math.hypot(x - point.x, y - point.y),
        Math.hypot(x - point.axisX, y - point.axisY)
      )
      if (distance < best) { best = distance; nearest = index }
    })
    return nearest
  }

  #show(index) {
    const entry = this.entries[index], point = this.points[index]
    if (!entry || !point) return

    this.activeIndex = index
    this.tooltipNameTarget.textContent = entry.name
    this.tooltipValueTarget.textContent = `${this.labelTarget.textContent.trim()} · ${entry.formatted}`
    const tooltip = this.tooltipTarget
    tooltip.hidden = false
    const x = this.chartTarget.offsetLeft + point.x
    const y = this.chartTarget.offsetTop + point.y
    const left = Math.max(8, Math.min(x - tooltip.offsetWidth / 2, this.visualTarget.clientWidth - tooltip.offsetWidth - 8))
    const above = y - tooltip.offsetHeight - 10
    const top = above < 8 ? y + 10 : above
    tooltip.style.left = `${left}px`
    tooltip.style.top = `${Math.max(8, Math.min(top, this.chartTarget.offsetTop + this.chartTarget.clientHeight - tooltip.offsetHeight - 8))}px`
  }
}
