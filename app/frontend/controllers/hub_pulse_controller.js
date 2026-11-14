import { Controller } from "@hotwired/stimulus"
import { dismissOnOutsidePress, placeCallout } from "../lib/hub_callout"
import { cssColor } from "../lib/css_color"
import { mixColors } from "../lib/hub_metrics"
import { LongPressScrub } from "../lib/long_press_scrub"
import { loadECharts } from "../lib/charts/echarts"
import { mountChart } from "../lib/charts/lifecycle"
import { chartFont } from "../lib/charts/theme"
import { tooltipBase } from "../lib/charts/tooltip"

// Smallest drawn amplitude (on the 0..100 score scale) of an active week, so a
// light week still reads as a capsule.
const MIN_ACTIVE_AMPLITUDE = 8
// How pale the lightest active capsule gets: 0 would be the surface itself.
const RAMP_FLOOR = 0.35
const AXIS_LIMIT = 122
const CHART_HEIGHT = 190
// A capsule never grows past this width, however few weeks a window holds,
// and never takes more than this share of its slot.
const MAX_CAPSULE_WIDTH = 28
const MAX_SLOT_SHARE = 0.6
const REST_DOT_SIZE = 5
const LABEL_SPACING = 90
// The x labels sit in a row under the plot; a label that would cross a
// window's edge is skipped rather than cut. Its half width is estimated from
// its length at the 11px label size.
const LABEL_ROW = 22
const LABEL_HALF_CHAR = 3.8
// One week never takes less than this many pixels, so a full window always
// overflows the card and the leftward scroll always has somewhere to go.
const MIN_WEEK_SLOT = 18
const WEEKS_PER_CHUNK = 104
// Drawn height is compressed (square root) so a quiet week stays visible next
// to an exceptional one; the tooltip and the table keep the linear score.
const AMPLITUDE_EXPONENT = 0.5
const SCROLL_STEP_SHARE = 0.85
const EDGE_EPSILON = 4
const SENTINEL_MARGIN = 600
const RESIZE_DEBOUNCE = 150
const RETRY_DELAY = 3000

// The personal hub's weekly intensity pulse (DESIGN.md §15.1): one mirrored
// capsule per week around a baseline, like an audio waveform. Height and tint
// both carry the week's 0..100 score — the strongest week full primary, a
// light one a pale nuance — and the selected period is the only thing that
// moves: its weeks keep the primary ramp while the rest of the history takes
// a neutral grey ramp, so switching windows never redraws the shape. The
// waveform spans the whole history; older windows are fetched from the pulse
// endpoint as the scroller reaches the left edge, each scored by the server
// against the same whole-history basis. ECharts loads on demand and every
// instance is disposed on disconnect.
//
// Selecting is the same for every input (§15.1): a tap or click anywhere in a
// week's column, a long-press slide, or the keyboard cursor selects the week
// and opens the callout over the card, whose button opens the workouts.
// Nothing on the chart itself navigates, so a mis-tap or a scroll never
// leaves the page.
export default class extends Controller {
  static values = { payload: Object }
  static targets = ["scroll", "charts", "sentinel", "skeleton", "live", "previous", "next", "latest",
    "callout", "calloutBody", "open", "openLabel"]

  connect() {
    this.connected = true
    this.generation = 0
    this.chunks = []
    this.points = this.payloadValue.points || []
    this.olderUrl = this.payloadValue.older_url || ""
    this.labels = this.payloadValue.labels || {}
    this.loading = false
    this.retryAt = 0
    this.cursor = null
    this.cursorChunk = null
    this.colors = null
    this.observing = false
    this.resetting = false
    this.resetAgain = false
    // Last known "scrolled to the present" state, kept across resizes.
    this.atEnd = true
    // Whether the newest window has been anchored at the right edge yet; a
    // rebuild before that first anchor must re-anchor instead of restoring.
    this.anchored = false
    this.reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)")
    // The floating tooltip follows a hovering pointer only; a touch screen
    // reads the selected week in the panel instead.
    this.canHover = window.matchMedia("(hover: hover)").matches
    this.abortController = new AbortController()
    this.onThemeChanged = () => this.#reset()
    this.onScroll = () => {
      this.#syncControls()
      this.#placeCallout()
    }
    this.stopDismiss = dismissOnOutsidePress(this.element, () => {
      if (this.cursor !== null) this.#clearCursor()
    })
    window.addEventListener("allure:theme-changed", this.onThemeChanged)
    this.scrollTarget.addEventListener("scroll", this.onScroll, { passive: true })
    this.scrub = new LongPressScrub(this.chartsTarget, {
      onStart: (x) => this.#selectAt(x),
      onMove: (x) => this.#selectAt(x)
    })
    this.#measure()
    this.#observeResize()
    this.#renderInitial()
  }

  disconnect() {
    this.connected = false
    this.generation += 1
    window.removeEventListener("allure:theme-changed", this.onThemeChanged)
    this.scrollTarget?.removeEventListener("scroll", this.onScroll)
    this.stopDismiss?.()
    this.scrub?.destroy()
    this.scrub = null
    this.abortController?.abort()
    this.abortController = null
    this.observer?.disconnect()
    this.observer = null
    this.observing = false
    this.resizeObserver?.disconnect()
    this.resizeObserver = null
    clearTimeout(this.resizeTimer)
    this.#destroyCharts()
  }

  previous() {
    if (this.scrollTarget.scrollLeft <= EDGE_EPSILON) this.#loadOlder()
    this.#scrollBy(-this.#step())
  }

  next() {
    this.#scrollBy(this.#step())
  }

  latest() {
    this.#scrollToEnd(true)
  }

  // A tap or click selects the week whose column it lands in, rest weeks
  // included; the selected week again clears the selection.
  select(event) {
    if (this.scrub?.consumeClick()) return

    const index = this.#indexAt(event.clientX)
    if (index === null) return
    if (index === this.cursor) return this.clear()

    this.#setCursor(index, { reveal: false })
  }

  clear() {
    this.#clearCursor()
  }

  keydown(event) {
    switch (event.key) {
      case "ArrowLeft":
        event.preventDefault()
        this.#moveCursor(-1)
        break
      case "ArrowRight":
        event.preventDefault()
        this.#moveCursor(1)
        break
      case "Home":
        event.preventDefault()
        this.#setCursor(0)
        break
      case "End":
        event.preventDefault()
        this.#setCursor(this.points.length - 1)
        break
      case "Enter":
      case " ":
        event.preventDefault()
        this.#openCursor()
        break
      case "Escape":
        if (this.cursor !== null) {
          event.preventDefault()
          this.#clearCursor()
        }
        break
    }
  }

  // Keyboard focus places the cursor; a pointer focusing the chart on its way
  // to a click leaves the choice to the click.
  focus() {
    if (this.points.length === 0) return
    if (!this.chartsTarget.matches(":focus-visible")) return
    if (this.cursor === null) this.#setCursor(this.#initialCursor())
    else this.#syncCursor()
  }

  // --- navigation ---------------------------------------------------------

  // The week under a viewport x: each window's plot spans its element width
  // (no side inset), so the column is the hit zone, not the drawn capsule.
  #indexAt(clientX) {
    let offset = 0
    for (const chunk of this.chunks) {
      const rect = chunk.element.getBoundingClientRect()
      if (clientX >= rect.left && clientX < rect.right) {
        const count = Math.max(chunk.points.length, 1)
        const local = Math.floor((clientX - rect.left) / (rect.width / count))
        return offset + Math.min(Math.max(local, 0), count - 1)
      }
      offset += chunk.points.length
    }
    return null
  }

  #selectAt(clientX) {
    const index = this.#indexAt(clientX)
    if (index !== null && index !== this.cursor) this.#setCursor(index, { reveal: false })
  }

  #openCursor() {
    if (this.cursor === null) return

    const point = this.points[this.cursor]
    if (point && !point.rest && point.url) this.#visit(point.url)
  }

  #visit(url) {
    if (window.Turbo) window.Turbo.visit(url)
    else window.location.assign(url)
  }

  // --- loading and layout -------------------------------------------------

  async #renderInitial() {
    if (this.points.length === 0) return

    const generation = ++this.generation
    await this.#addChunk(this.points, { prepend: false, stretch: !this.olderUrl })
    if (!this.connected || generation !== this.generation) return

    this.#scrollToEnd(false)
    this.anchored = true
    // Observe only after the right anchor, so the sentinel does not fire an
    // older window on every page load.
    this.#observeSentinel()
    this.#syncControls()
  }

  async #loadOlder() {
    if (this.loading || !this.olderUrl || Date.now() < this.retryAt) return false

    this.loading = true
    this.#setLoading(true)
    const scrollLeft = this.scrollTarget.scrollLeft
    const cursor = this.cursor
    try {
      const response = await fetch(this.olderUrl, {
        headers: { Accept: "application/json" },
        signal: this.abortController.signal
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const data = await response.json()
      if (!this.connected) return false

      const points = data.points || []
      this.olderUrl = data.older_url || ""
      if (points.length === 0) return false

      const record = await this.#addChunk(points, { prepend: true, stretch: false, animate: false })
      if (!this.connected || !record) return false

      this.points = [ ...points, ...this.points ]
      this.scrollTarget.scrollLeft = scrollLeft + record.width
      if (cursor !== null) {
        this.cursor = cursor + points.length
        this.#syncCursor()
      }
      return true
    } catch (error) {
      if (error.name !== "AbortError") this.retryAt = Date.now() + RETRY_DELAY
      return false
    } finally {
      this.loading = false
      this.#setLoading(false)
      this.#syncControls()
    }
  }

  #observeSentinel() {
    if (this.observing) return

    this.observing = true
    this.observer = new IntersectionObserver(
      (entries) => entries.forEach((entry) => { if (entry.isIntersecting) this.#loadOlder() }),
      { root: this.scrollTarget, rootMargin: `0px 0px 0px ${SENTINEL_MARGIN}px` }
    )
    this.observer.observe(this.sentinelTarget)
  }

  #observeResize() {
    this.resizeObserver = new ResizeObserver(() => this.#scheduleResize())
    this.resizeObserver.observe(this.scrollTarget)
  }

  #scheduleResize() {
    clearTimeout(this.resizeTimer)
    this.resizeTimer = setTimeout(() => this.#handleResize(), RESIZE_DEBOUNCE)
  }

  async #handleResize() {
    if (!this.connected) return

    const width = this.scrollTarget.clientWidth
    const slot = this.#slotFor(width)
    if (width === this.viewportWidth && slot === this.slotPx) return

    this.viewportWidth = width
    this.slotPx = slot
    await this.#reset()
  }

  // Theme change and viewport change both rebuild every window from the same
  // loaded weeks, at the new resolved colours and pixel pitch.
  async #reset() {
    if (!this.connected || this.chunks.length === 0) return
    if (this.resetting) {
      this.resetAgain = true
      return
    }

    this.resetting = true
    this.generation += 1
    const chunks = this.chunks.map((chunk) => chunk.points)
    const scroller = this.scrollTarget
    const scrollLeft = scroller.scrollLeft
    // The last known state, not a measurement: by the time the observer runs,
    // the viewport may already have shrunk and the old scrollLeft no longer
    // looks like the end.
    const atEnd = this.atEnd
    this.#destroyCharts()
    for (const points of chunks) {
      await this.#addChunk(points, { prepend: false, stretch: chunks.length === 1 && !this.olderUrl, animate: false })
      if (!this.connected) return
    }
    this.points = chunks.flat()
    if (this.anchored && !atEnd) scroller.scrollLeft = scrollLeft
    else this.#scrollToEnd(false)
    this.anchored = true
    this.#observeSentinel()
    if (this.cursor !== null) this.#syncCursor()
    this.#syncControls()
    this.resetting = false
    if (this.resetAgain) {
      this.resetAgain = false
      this.#reset()
    }
  }

  #measure() {
    this.viewportWidth = this.scrollTarget.clientWidth
    this.slotPx = this.#slotFor(this.viewportWidth)
  }

  #slotFor(width) {
    return Math.max(MIN_WEEK_SLOT, Math.ceil(width / WEEKS_PER_CHUNK))
  }

  #step() {
    return Math.max(120, this.scrollTarget.clientWidth * SCROLL_STEP_SHARE)
  }

  #scrollBy(delta) {
    this.scrollTarget.scrollBy({ left: delta, behavior: this.reducedMotion.matches ? "auto" : "smooth" })
  }

  #scrollToEnd(smooth) {
    this.scrollTarget.scrollTo({
      left: this.scrollTarget.scrollWidth,
      behavior: smooth && !this.reducedMotion.matches ? "smooth" : "auto"
    })
  }

  #syncControls() {
    const scroller = this.scrollTarget
    const atStart = scroller.scrollLeft <= EDGE_EPSILON
    const atEnd = scroller.scrollLeft + scroller.clientWidth >= scroller.scrollWidth - EDGE_EPSILON
    this.atEnd = atEnd

    if (this.hasPreviousTarget) this.previousTarget.disabled = atStart && !this.olderUrl
    if (this.hasNextTarget) this.nextTarget.hidden = atEnd
    if (this.hasLatestTarget) this.latestTarget.hidden = atEnd
  }

  #setLoading(loading) {
    if (this.hasSkeletonTarget) this.skeletonTarget.hidden = !loading
  }

  // --- charts -------------------------------------------------------------

  async #addChunk(points, { prepend, stretch, animate = true }) {
    const echarts = await loadECharts()
    if (!this.connected) return null

    const width = this.#chunkWidth(points.length, stretch)
    const element = document.createElement("div")
    element.className = "hub-pulse-chart"
    element.style.width = `${width}px`

    const record = { element, chart: null, release: null, points, width }
    if (prepend) {
      this.chartsTarget.prepend(element)
      this.chunks.unshift(record)
    } else {
      this.chartsTarget.append(element)
      this.chunks.push(record)
    }

    // Every window has its own fixed size: the scroller's observer rebuilds
    // them all when the pitch changes, so none observes itself.
    const mounted = mountChart(echarts, element, { width, height: CHART_HEIGHT, autoResize: false })
    record.chart = mounted.chart
    record.release = mounted.release
    record.chart.setOption(this.#options(record, width, animate))
    return record
  }

  #chunkWidth(count, stretch) {
    const width = count * this.slotPx
    return stretch && width < this.viewportWidth ? this.viewportWidth : width
  }

  #destroyCharts() {
    this.chunks.forEach((chunk) => {
      chunk.release?.()
      chunk.element?.remove()
    })
    this.chunks = []
    this.cursorChunk = null
  }

  // No side inset: each window's plot spans its full element width, so two
  // consecutive windows meet without a seam and the timeline stays
  // continuous. The y range keeps symmetric headroom above and below the
  // 100 % capsule for the cursor label, so the baseline stays at the middle.
  #options(record, width, animate) {
    const points = record.points
    const colors = this.#colors()
    const { barWidth, radius } = this.#capsule(points.length, width)
    const ticks = Math.max(2, Math.min(points.length, Math.floor(width / LABEL_SPACING)))
    const every = Math.max(1, Math.ceil(points.length / ticks))
    const slot = width / Math.max(points.length, 1)
    const name = this.labels.intensity || ""
    const bar = (sign) => ({
      type: "bar",
      name,
      stack: "pulse",
      barWidth,
      data: points.map((point) => ({
        value: sign * this.#amplitude(point),
        itemStyle: { color: this.#tint(point, colors) }
      })),
      itemStyle: { borderRadius: sign > 0 ? [ radius, radius, 0, 0 ] : [ 0, 0, radius, radius ] },
      emphasis: { itemStyle: { opacity: 0.8 } }
    })

    return {
      animation: animate && !this.reducedMotion.matches,
      animationDuration: 300,
      textStyle: { fontFamily: chartFont() },
      grid: { left: 0, right: 0, top: 0, bottom: LABEL_ROW, outerBoundsMode: "none" },
      xAxis: {
        type: "category",
        data: points.map((_point, index) => String(index)),
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: {
          color: colors.muted,
          fontSize: 11,
          hideOverlap: true,
          formatter: (_value, index) => points[index]?.label ?? "",
          interval: (index) => {
            if (index % every !== 0) return false
            const centre = (index + 0.5) * slot
            const half = String(points[index]?.label ?? "").length * LABEL_HALF_CHAR + 2
            return centre - half >= 0 && centre + half <= width
          }
        }
      },
      yAxis: { type: "value", min: -AXIS_LIMIT, max: AXIS_LIMIT, show: false },
      tooltip: tooltipBase({
        show: this.canHover,
        trigger: "axis",
        axisPointer: { type: "none" },
        formatter: (params) => this.#tooltip(points, params[0]?.dataIndex)
      }),
      series: [ bar(1), bar(-1), this.#marks(points, -1) ]
    }
  }

  #colors() {
    const muted = cssColor("--allure-text-muted", "#9ca3af")
    this.colors = {
      primary: cssColor("--primary"),
      surface: cssColor("--allure-surface", "#ffffff"),
      muted,
      baseline: cssColor("--allure-border", muted)
    }
    return this.colors
  }

  #series(points, colors) {
    const half = (sign) => points.map((point) => ({
      x: point.label,
      y: sign * this.#amplitude(point),
      fillColor: this.#tint(point, colors)
    }))
    const name = this.labels.intensity || ""

    return [
      { name, data: half(1) },
      { name, data: half(-1) }
    ]
  }

  #amplitude(point) {
    if (point.rest) return 0

    const share = Math.max(point.score, 0) / 100
    return Math.max(Math.pow(share, AMPLITUDE_EXPONENT) * 100, MIN_ACTIVE_AMPLITUDE)
  }

  #tint(point, colors) {
    const ratio = RAMP_FLOOR + (1 - RAMP_FLOOR) * (point.score / 100)
    return mixColors(point.in_period ? colors.primary : colors.muted, colors.surface, ratio)
  }

  // The capsule width follows the slot a week gets, capped in pixels so a
  // five-week window does not draw slabs, and the radius is half of it so
  // every capsule ends in a true half-circle.
  #capsule(count, width) {
    const slot = width / Math.max(count, 1)
    const share = Math.min(MAX_SLOT_SHARE, MAX_CAPSULE_WIDTH / slot)
    return { barWidth: `${(share * 100).toFixed(1)}%`, radius: Math.max(2, Math.floor((slot * share) / 2)) }
  }

  // Rest weeks draw nothing; a muted dot on the baseline keeps their slot
  // visible so the rhythm — and the gaps in it — stays readable. The period
  // peak is named by the reading line under the chart, not marked on it; the
  // keyboard cursor is a dashed guide with the week's own label. All of it
  // lives on one series, so moving the cursor updates that series alone.
  #marks(points, cursorLocal) {
    const colors = this.colors || this.#colors()
    const cursor = cursorLocal >= 0 && points[cursorLocal]
    const line = (data, lineStyle) => data.map((item) => ({ ...item, lineStyle }))

    return {
      id: "marks",
      type: "scatter",
      silent: true,
      tooltip: { show: false },
      symbolSize: REST_DOT_SIZE,
      itemStyle: { color: colors.muted },
      data: points.flatMap((point, index) => (point.rest ? [ [ index, 0 ] ] : [])),
      markLine: {
        silent: true,
        symbol: "none",
        animation: false,
        label: { show: false },
        data: [
          ...line([ { yAxis: 0 } ], { color: colors.baseline, width: 1, type: "solid", opacity: 1 }),
          ...(cursor ? line([ { xAxis: cursorLocal } ], { color: colors.primary, width: 1, type: [ 4, 4 ], opacity: 0.9 }) : [])
        ]
      },
      markPoint: {
        silent: true,
        animation: false,
        data: cursor ? [ {
          coord: [ cursorLocal, AXIS_LIMIT ],
          symbol: "circle",
          symbolSize: 0,
          label: {
            show: true,
            formatter: () => points[cursorLocal].label,
            position: "bottom",
            distance: 2,
            align: this.#edgeAlign(cursorLocal, points.length),
            color: colors.primary,
            fontSize: 11,
            fontWeight: 600
          }
        } ] : []
      }
    }
  }

  // The cursor label is centred on its week and would be clipped by the chart
  // edge when that week is the first or last one.
  #edgeAlign(index, count) {
    if (index <= 1) return "left"
    if (index >= count - 2) return "right"
    return "center"
  }

  #tooltip(points, dataPointIndex) {
    const point = points[dataPointIndex]
    if (!point) return ""

    return `<div class="hub-chart-tooltip">
      <div class="hub-chart-tooltip-title">${escape(point.tooltip_label)} · ${escape(point.score_label)}</div>
      <div class="hub-chart-tooltip-detail">${escape(point.detail)}</div>
    </div>`
  }

  // --- keyboard cursor ----------------------------------------------------

  #initialCursor() {
    const peak = this.points.findIndex((point) => point.peak)
    if (peak >= 0) return peak

    const active = this.points.findLastIndex((point) => !point.rest)
    return active >= 0 ? active : this.points.length - 1
  }

  #moveCursor(delta) {
    if (this.cursor === null) return this.#setCursor(this.#initialCursor())

    const index = this.cursor + delta
    if (index < 0) {
      if (!this.olderUrl) return this.#setCursor(0)
      this.#loadOlder().then((loaded) => { if (loaded) this.#setCursor(this.cursor - 1) })
      return
    }
    this.#setCursor(Math.min(index, this.points.length - 1))
  }

  // A pointer selection never scrolls the waveform under the finger; the
  // keyboard cursor keeps its week in view.
  #setCursor(index, { reveal = true } = {}) {
    if (this.points.length === 0) return

    this.cursor = Math.max(0, Math.min(index, this.points.length - 1))
    this.#syncCursor({ reveal })
    const point = this.points[this.cursor]
    if (point && this.hasLiveTarget) this.liveTarget.textContent = this.#announcement(point)
    this.#renderPanel(point)
  }

  // The callout follows the selection (§15.1): the selected week's label,
  // score and facts, and the button to its workouts (none for a rest week).
  // The reading line under the chart never changes; with no selection the
  // callout is closed and nothing offers to open a week the viewer did not
  // choose.
  #renderPanel(point) {
    if (!this.hasCalloutTarget) return

    if (!point) {
      this.calloutTarget.hidden = true
      return
    }

    const title = document.createElement("strong")
    title.className = "d-block hub-callout__title"
    title.textContent = point.tooltip_label
    const detail = document.createElement("span")
    detail.className = "d-block hub-callout__detail"
    detail.textContent = point.rest ? point.score_label : `${point.score_label} · ${point.detail}`
    this.calloutBodyTarget.replaceChildren(title, detail)
    this.#setOpen(point.rest ? null : point.url, point.open_label, point.rest || !point.url)
    this.#placeCallout()
  }

  #setOpen(url, label, hidden) {
    if (!this.hasOpenTarget) return

    this.openTarget.hidden = hidden
    if (hidden) return
    this.openTarget.setAttribute("href", url)
    this.openLabelTarget.textContent = label
  }

  // Points at the selected week's column, above the waveform when the card
  // has the room. A week scrolled out of the frame hides the callout until
  // it comes back; the selection itself stays.
  #placeCallout() {
    if (!this.hasCalloutTarget || this.cursor === null) return

    const { chunk, local } = this.#locate(this.cursor)
    if (!chunk) return
    const rect = chunk.element.getBoundingClientRect()
    const x = rect.left + (local + 0.5) * (rect.width / Math.max(chunk.points.length, 1))
    const frame = this.scrollTarget.getBoundingClientRect()
    const visible = x >= frame.left && x <= frame.right
    this.calloutTarget.hidden = !visible
    if (!visible) return

    placeCallout(this.calloutTarget, { x, top: frame.top, bottom: frame.bottom }, this.element.closest(".card"))
  }

  #syncCursor({ reveal = true } = {}) {
    const { chunk, local } = this.#locate(this.cursor)
    if (this.cursorChunk && this.cursorChunk !== chunk) {
      this.#drawCursor(this.cursorChunk, -1)
    }
    if (!chunk) return

    this.#drawCursor(chunk, local)
    this.cursorChunk = chunk
    if (reveal) this.#revealCursor(chunk, local)
    this.#placeCallout()
  }

  #drawCursor(chunk, local) {
    if (!chunk.chart || chunk.chart.isDisposed()) return
    chunk.chart.setOption({ series: [ this.#marks(chunk.points, local) ] })
  }

  #clearCursor() {
    if (this.cursorChunk) this.#drawCursor(this.cursorChunk, -1)
    this.cursorChunk = null
    this.cursor = null
    if (this.hasLiveTarget) this.liveTarget.textContent = ""
    this.#renderPanel(null)
  }

  #locate(index) {
    let offset = 0
    for (const chunk of this.chunks) {
      if (index < offset + chunk.points.length) return { chunk, local: index - offset }
      offset += chunk.points.length
    }
    return { chunk: null, local: -1 }
  }

  #revealCursor(chunk, local) {
    const before = this.chunks.slice(0, this.chunks.indexOf(chunk)).reduce((sum, item) => sum + item.width, 0)
    const slot = chunk.width / Math.max(chunk.points.length, 1)
    const x = before + (local + 0.5) * slot
    const left = this.scrollTarget.scrollLeft
    const right = left + this.scrollTarget.clientWidth
    if (x < left + 24) this.scrollTarget.scrollLeft = Math.max(0, x - 48)
    else if (x > right - 24) this.scrollTarget.scrollLeft = x - this.scrollTarget.clientWidth + 48
  }

  #announcement(point) {
    const state = point.in_period ? this.labels.in_period : this.labels.history
    const detail = point.rest ? point.score_label : `${point.score_label}. ${point.detail}`
    return [ point.tooltip_label, state, detail ].filter(Boolean).join(". ")
  }
}

function escape(text) {
  return String(text ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
}
