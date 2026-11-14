import { Controller } from "@hotwired/stimulus"
import { dismissOnOutsidePress, placeCallout } from "../lib/hub_callout"
import { LongPressScrub } from "../lib/long_press_scrub"

const METRES_PER_KILOMETRE = 1000.0
const METRES_PER_MILE = 1609.344
const MIN_WEEKS = 12
const MIN_CELL = 13
const GRID_GAP = 3
const DAYS_PER_WEEK = 7
const MILLISECONDS_PER_DAY = 24 * 60 * 60 * 1000
const METRICS = ["distance", "duration", "count"]

// Personal-hub activity calendar (DESIGN.md §15.3). Fetches the day-bucketed
// stats dataset and renders a week heatmap (plain DOM, no chart library)
// whose number of columns follows the available width: a wider card shows
// more weeks, never bigger cells — the 13px cell is the constant. Intensity
// encodes the selected metric in five steps; every non-empty day links to
// that day's workouts and carries a full accessible name, so intensity is
// never colour-only. Weeks align to the viewer's week-start preference and
// future days render blank. The radio metric selector, the paging controls
// and the rich tooltip all re-render from the already-fetched buckets.
//
// Selecting a day is the same for every input: a tap, a click, a long-press
// slide across the grid, or Enter on a focused day selects it and opens its
// panel under the grid, whose button leads to the day's workouts. Enter on
// the already-selected day follows its link, and a modified click (new tab)
// keeps the native link behaviour.
export default class extends Controller {
  static values = {
    url: String,
    dayUrl: String,
    workoutUrl: String,
    weekStart: String,
    unitSystem: String,
    locale: String,
    label: String,
    workoutOne: String,
    workoutOther: String,
    metric: { type: String, default: "duration" },
    sports: Object,
    total: String,
    openOne: String,
    openOther: String,
    rest: String
  }
  static targets = ["container", "loading", "empty", "error", "range", "today", "next", "metric",
    "detail", "detailBody", "open", "openLabel"]

  connect() {
    this.connected = true
    this.abortController = new AbortController()
    this.tooltips = new Map()
    this.activeMetric = METRICS.includes(this.metricValue) ? this.metricValue : "duration"
    this.buckets = []
    this.byDate = new Map()
    this.selectedDate = null
    this.windowEnd = startOfDay(new Date())
    this.weeksShown = MIN_WEEKS
    this.#bindTooltipEvents()
    this.#observeResize()
    this.scrub = new LongPressScrub(this.containerTarget, {
      onStart: (x, y) => this.#selectAt(x, y),
      onMove: (x, y) => this.#selectAt(x, y)
    })
    this.stopDismiss = dismissOnOutsidePress(this.element, () => {
      if (this.selectedDate) this.clear()
    })
    this.#showState("loading")
    this.#load()
  }

  disconnect() {
    this.connected = false
    this.abortController?.abort()
    this.abortController = null
    this.resizeObserver?.disconnect()
    cancelAnimationFrame(this.resizeFrame)
    this.scrub?.destroy()
    this.scrub = null
    this.stopDismiss?.()
    this.#unbindTooltipEvents()
    this.#disposeTooltips()
  }

  select(event) {
    const cell = event.target.closest(".stats-calendar-day[data-date]")
    if (!cell) return
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button > 0) return
    if (this.scrub?.consumeClick()) return event.preventDefault()

    const date = cell.dataset.date
    // A keyboard activation (no pointer, `detail` 0) of the selected day opens it.
    if (event.detail === 0 && date === this.selectedDate) return

    event.preventDefault()
    if (date === this.selectedDate) return this.clear()
    this.#selectDay(date)
  }

  keydown(event) {
    if (event.key !== "Escape" || !this.selectedDate) return

    event.preventDefault()
    this.clear()
  }

  clear() {
    this.selectedDate = null
    this.#markSelected()
    if (this.hasDetailTarget) this.detailTarget.hidden = true
  }

  #selectAt(x, y) {
    const cell = document.elementFromPoint(x, y)?.closest(".stats-calendar-day[data-date]")
    if (!cell || !this.containerTarget.contains(cell) || cell.dataset.date === this.selectedDate) return

    this.#selectDay(cell.dataset.date)
  }

  #selectDay(date) {
    this.selectedDate = date
    this.#hideTooltips()
    this.#markSelected()
    this.#renderDetail()
  }

  #markSelected() {
    this.containerTarget.querySelectorAll(".stats-calendar-day.is-selected").forEach((cell) => {
      cell.classList.remove("is-selected")
      if (cell.tagName === "A") cell.removeAttribute("aria-current")
    })
    if (!this.selectedDate) return

    const cell = this.containerTarget.querySelector(`.stats-calendar-day[data-date="${this.selectedDate}"]`)
    if (!cell) return
    cell.classList.add("is-selected")
    if (cell.tagName === "A") cell.setAttribute("aria-current", "date")
  }

  // The callout is the tooltip's content made persistent, plus the day's
  // workouts button; an empty day says so and offers no button.
  #renderDetail() {
    if (!this.hasDetailTarget || !this.selectedDate) return

    const date = fromISODate(this.selectedDate)
    const entry = this.byDate.get(this.selectedDate)
    let body
    if (entry && entry.count > 0) {
      const level = Number(this.containerTarget.querySelector(`[data-date="${this.selectedDate}"]`)?.dataset.level || 1)
      body = this.#dayDetail(date, entry, level)
    } else {
      body = document.createElement("div")
      const title = document.createElement("strong")
      title.textContent = this.#formatDate(date, { weekday: "long", day: "numeric", month: "long" })
      const rest = document.createElement("div")
      rest.className = "small hub-callout__detail"
      rest.textContent = this.restValue
      body.append(title, rest)
    }
    this.detailBodyTarget.replaceChildren(body)

    if (this.hasOpenTarget) {
      const hidden = !entry || entry.count === 0
      this.openTarget.hidden = hidden
      if (!hidden) {
        this.openTarget.href = this.#dayUrl(this.selectedDate, entry)
        this.openLabelTarget.textContent = entry.count === 1 ? this.openOneValue : this.openOtherValue
      }
    }
    this.detailTarget.hidden = false
    this.#placeDetail()
  }

  // The callout points at the selected day's cell, above it when the card
  // has the room, below it otherwise.
  #placeDetail() {
    const cell = this.containerTarget.querySelector(`.stats-calendar-day[data-date="${this.selectedDate}"]`)
    if (!cell) return

    const rect = cell.getBoundingClientRect()
    placeCallout(this.detailTarget, { x: rect.left + rect.width / 2, top: rect.top, bottom: rect.bottom }, this.element)
  }

  selectMetric(event) {
    const metric = event.target.value
    if (!METRICS.includes(metric) || metric === this.activeMetric) return

    this.activeMetric = metric
    this.#syncMetricControls()
    this.#render()
  }

  // The segmented radios (md and up) and the native select (phones) drive the
  // same metric; whichever changed, the other follows, so a resize never shows
  // a stale choice.
  #syncMetricControls() {
    this.metricTargets.forEach((control) => {
      if (control.type === "radio") control.checked = control.value === this.activeMetric
      else control.value = this.activeMetric
    })
  }

  previousWindow() {
    this.windowEnd = addDays(this.windowEnd, -(this.weeksShown * DAYS_PER_WEEK))
    this.#render()
  }

  nextWindow() {
    if (this.#atCurrentWindow()) return

    const today = startOfDay(new Date())
    this.windowEnd = addDays(this.windowEnd, this.weeksShown * DAYS_PER_WEEK)
    if (this.windowEnd > today) this.windowEnd = today
    this.#render()
  }

  currentWindow() {
    this.windowEnd = startOfDay(new Date())
    this.#render()
  }

  async #load() {
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "application/json" },
        signal: this.abortController.signal
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const data = await response.json()
      if (!this.connected) return

      this.buckets = data.buckets || []
      if (!this.buckets.length) return this.#showState("empty")
      this.#render()
      this.#showState("ready")
    } catch (error) {
      if (error?.name === "AbortError") return
      if (this.connected) this.#showState("error")
    }
  }

  #render() {
    this.#disposeTooltips()
    this.weeksShown = this.#weeksForWidth()

    const byDate = this.#bucketsByDate()
    this.byDate = byDate
    const today = startOfDay(new Date())
    // The window ends on the viewer's last day and grows to the left, so the
    // grid always fills the card width.
    const gridStart = weekStartOnOrBefore(addDays(this.windowEnd, -((this.weeksShown - 1) * DAYS_PER_WEEK)), this.weekStartValue)
    const firstDay = toISODate(gridStart)
    const lastDay = toISODate(this.windowEnd)
    // The ramp reflects the visible window only; older buckets would
    // otherwise skew the quartiles of a grid that never shows them.
    const thresholds = this.#thresholds(
      [ ...byDate.entries() ]
        .filter(([ date ]) => date >= firstDay && date <= lastDay)
        .map(([ _date, entry ]) => this.#metricValue(entry))
    )

    const grid = document.createElement("div")
    grid.className = "stats-calendar-grid"

    for (let week = 0; week < this.weeksShown; week++) {
      const column = document.createElement("div")
      column.className = "stats-calendar-week"
      for (let day = 0; day < DAYS_PER_WEEK; day++) {
        const date = addDays(gridStart, week * DAYS_PER_WEEK + day)
        column.appendChild(this.#dayCell(date, today, byDate.get(toISODate(date)), thresholds))
      }
      grid.appendChild(column)
    }

    const region = document.createElement("div")
    region.className = "stats-calendar-region"
    region.setAttribute("role", "group")
    region.setAttribute("aria-label", this.labelValue)
    // The week count lives on the region so the grid and its year anchors
    // share one column template.
    region.style.setProperty("--stats-calendar-weeks", this.weeksShown)
    region.appendChild(grid)
    region.appendChild(this.#yearRow(gridStart))
    this.containerTarget.replaceChildren(region)

    this.#updateRange(gridStart, this.windowEnd)
    this.#updateNavigation(today)

    // A selection survives a metric change or a resize while its day is
    // still drawn; paging it out of the window clears it.
    if (this.selectedDate && region.querySelector(`[data-date="${this.selectedDate}"]`)) {
      this.#markSelected()
      this.#renderDetail()
    } else if (this.selectedDate) {
      this.clear()
    }
  }

  // Year anchors under the grid: each year is labelled on the column holding
  // its first visible day, so a window that spans years still reads as a
  // timeline. Decorative — the printed range below the grid is the text
  // equivalent.
  #yearRow(gridStart) {
    const row = document.createElement("div")
    row.className = "stats-calendar-years"
    row.setAttribute("aria-hidden", "true")

    const cells = []
    for (let week = 0; week < this.weeksShown; week++) {
      const cell = document.createElement("span")
      cells.push(cell)
      row.appendChild(cell)
    }

    const lastDay = addDays(gridStart, this.weeksShown * DAYS_PER_WEEK - 1)
    // Newest first: a first column that crosses January 1st carries the year
    // that begins there, not the handful of December days at the window edge.
    for (let year = lastDay.getFullYear(); year >= gridStart.getFullYear(); year--) {
      const firstOfYear = new Date(year, 0, 1)
      const firstVisible = firstOfYear >= gridStart ? firstOfYear : gridStart
      const days = Math.round((firstVisible - gridStart) / MILLISECONDS_PER_DAY)
      const cell = cells[Math.floor(days / DAYS_PER_WEEK)]
      if (!cell || cell.textContent) continue

      cell.className = "stats-calendar-year"
      cell.textContent = String(year)
    }
    return row
  }

  #weeksForWidth() {
    const width = this.containerTarget.clientWidth || this.element.clientWidth
    const fit = Math.floor((width + GRID_GAP) / (MIN_CELL + GRID_GAP))
    return Math.max(MIN_WEEKS, fit)
  }

  #observeResize() {
    if (typeof ResizeObserver === "undefined") return

    this.resizeObserver = new ResizeObserver(() => {
      cancelAnimationFrame(this.resizeFrame)
      this.resizeFrame = requestAnimationFrame(() => {
        if (!this.connected || !this.buckets.length) return
        if (this.#weeksForWidth() === this.weeksShown) return

        this.#render()
      })
    })
    this.resizeObserver.observe(this.element)
  }

  #bucketsByDate() {
    const byDate = new Map()
    for (const row of this.buckets) {
      const entry = byDate.get(row.period) || { count: 0, distance: 0, duration: 0, sports: new Map() }
      entry.count += row.total_workouts
      if (row.workout_id) entry.workoutId = row.workout_id
      entry.distance += row.total_distance
      entry.duration += row.total_duration

      const sport = entry.sports.get(row.sport_id) || { count: 0, distance: 0, duration: 0 }
      sport.count += row.total_workouts
      sport.distance += row.total_distance
      sport.duration += row.total_duration
      entry.sports.set(row.sport_id, sport)
      byDate.set(row.period, entry)
    }
    return byDate
  }

  #dayCell(date, today, entry, thresholds) {
    // Days after the visible window end (a past window) and after today are
    // blank, never empty: no workout could have happened there yet.
    if (date > this.windowEnd || date > today) {
      const cell = document.createElement("span")
      cell.className = "stats-calendar-day stats-calendar-future"
      return cell
    }

    const count = entry ? entry.count : 0
    if (count === 0) {
      // Still selectable by pointer, so a tap confirms a rest day; it stays
      // out of the tab order and the accessibility tree like before.
      const cell = document.createElement("span")
      cell.className = "stats-calendar-day stats-calendar-level-0"
      cell.setAttribute("aria-hidden", "true")
      cell.dataset.date = toISODate(date)
      return cell
    }

    const value = this.#metricValue(entry)
    // A workout without a positive value for the active metric still gets the
    // lightest tint rather than vanishing into the empty cells.
    const level = value > 0 ? this.#level(value, thresholds) : 1
    const label = this.#dayLabel(date, count, value)
    const link = document.createElement("a")
    link.className = `stats-calendar-day stats-calendar-level-${level}`
    link.href = this.#dayUrl(toISODate(date), entry)
    link.setAttribute("aria-label", label)
    link.dataset.date = toISODate(date)
    link.dataset.level = String(level)
    link.dataset.tooltip = this.#dayDetail(date, entry, level).outerHTML
    return link
  }

  // A day with one activity opens it; any other day opens its list.
  #dayUrl(isoDate, entry) {
    if (entry.count === 1 && entry.workoutId && this.hasWorkoutUrlValue) {
      return this.workoutUrlValue.replace("__id__", encodeURIComponent(entry.workoutId))
    }
    return this.dayUrlValue.replaceAll("__date__", isoDate)
  }

  #metricValue(entry) {
    if (this.activeMetric === "duration") return entry.duration
    if (this.activeMetric === "count") return entry.count
    return entry.distance
  }

  #thresholds(values) {
    // Activity counts have no meaningful quartiles: a fixed one-to-four ramp
    // reads the same whatever the volume.
    return this.activeMetric === "count" ? [ 1, 2, 3 ] : distanceThresholds(values)
  }

  #level(value, thresholds) {
    if (this.activeMetric === "count") return Math.min(Math.max(Math.round(value), 1), 4)
    return intensityLevel(value, thresholds)
  }

  #dayLabel(date, count, value) {
    const noun = count === 1 ? this.workoutOneValue : this.workoutOtherValue
    const parts = [ this.#formatDate(date), `${count} ${noun}` ]
    if (this.activeMetric === "distance") parts.push(formatDistance(value, this.unitSystemValue, this.localeValue))
    if (this.activeMetric === "duration") parts.push(formatDuration(value))
    return parts.join(", ")
  }

  // The day's detail: the hover tooltip's content and the selection panel's.
  #dayDetail(date, entry, level) {
    const wrapper = document.createElement("div")
    wrapper.className = "hub-calendar-tooltip"

    const header = document.createElement("div")
    header.className = "d-flex align-items-center gap-2 mb-1"
    const swatch = document.createElement("span")
    swatch.className = `hub-calendar-swatch stats-calendar-level-${level}`
    const title = document.createElement("strong")
    title.textContent = this.#formatDate(date, { weekday: "long", day: "numeric", month: "long" })
    header.append(swatch, title)
    wrapper.appendChild(header)

    const sports = [ ...entry.sports.entries() ].sort(([, left], [, right]) => this.#metricValue(right) - this.#metricValue(left))
    for (const [ sportId, sport ] of sports) {
      const row = document.createElement("div")
      row.className = "d-flex align-items-center gap-1 small"
      const info = this.sportsValue[String(sportId)]
      if (info) {
        // The server renders the sport's own SVG partial; the tooltip only
        // places it. Never build a sport glyph from the icon font here.
        const icon = document.createElement("span")
        icon.className = "sport-icon"
        icon.setAttribute("aria-hidden", "true")
        icon.innerHTML = info.icon
        const name = document.createElement("span")
        name.textContent = info.name
        row.append(icon, name)
      }
      const value = document.createElement("span")
      value.className = "ms-auto text-nowrap"
      value.textContent = this.#tooltipValue(sport)
      row.appendChild(value)
      wrapper.appendChild(row)
    }

    const total = document.createElement("div")
    total.className = "border-top mt-1 pt-1 small"
    total.textContent = `${this.totalValue} : ${this.#tooltipValue(entry)}`
    wrapper.appendChild(total)
    return wrapper
  }

  #tooltipValue(entry) {
    const parts = [ formatDistance(entry.distance, this.unitSystemValue, this.localeValue) ]
    if (entry.duration > 0) parts.push(formatDuration(entry.duration))
    return parts.join(" · ")
  }

  #formatDate(date, options = { day: "numeric", month: "long" }) {
    return new Intl.DateTimeFormat(this.localeValue, options).format(date)
  }

  #updateRange(start, end) {
    if (!this.hasRangeTarget) return

    const format = new Intl.DateTimeFormat(this.localeValue, { month: "short", year: "numeric" })
    this.rangeTarget.textContent = `${format.format(start)} – ${format.format(end)}`
  }

  #updateNavigation(today) {
    const current = toISODate(this.windowEnd) >= toISODate(today)
    if (this.hasTodayTarget) this.todayTarget.hidden = current
    if (this.hasNextTarget) this.nextTarget.disabled = current
  }

  #atCurrentWindow() {
    return toISODate(this.windowEnd) >= toISODate(startOfDay(new Date()))
  }

  // The tooltip previews a day for a hovering mouse and for keyboard focus
  // only: on touch the selection panel carries the same content, and an
  // emulated hover would leave a tooltip stuck over the grid.
  #bindTooltipEvents() {
    this.onPointerOver = (event) => {
      if (event.pointerType !== "mouse") return
      const cell = event.target.closest(".stats-calendar-day[data-tooltip]")
      if (cell) this.#showTooltip(cell)
    }
    this.onPointerOut = (event) => {
      const cell = event.target.closest(".stats-calendar-day[data-tooltip]")
      if (cell) this.#hideTooltip(cell)
    }
    this.onFocusIn = (event) => {
      if (event.target.matches(".stats-calendar-day[data-tooltip]:focus-visible")) this.#showTooltip(event.target)
    }
    this.onFocusOut = (event) => {
      if (event.target.matches(".stats-calendar-day[data-tooltip]")) this.#hideTooltip(event.target)
    }
    this.element.addEventListener("pointerover", this.onPointerOver)
    this.element.addEventListener("pointerout", this.onPointerOut)
    this.element.addEventListener("focusin", this.onFocusIn)
    this.element.addEventListener("focusout", this.onFocusOut)
  }

  #unbindTooltipEvents() {
    this.element.removeEventListener("pointerover", this.onPointerOver)
    this.element.removeEventListener("pointerout", this.onPointerOut)
    this.element.removeEventListener("focusin", this.onFocusIn)
    this.element.removeEventListener("focusout", this.onFocusOut)
  }

  #hideTooltips() {
    for (const tooltip of this.tooltips.values()) tooltip.hide()
  }

  // Bootstrap tooltips are created on first hover and reused, so an adaptive
  // grid never pays for one instance per cell. Content is server-generated
  // markup (sport SVGs, text and numbers), never user input, so Bootstrap's
  // tag allow-list is disabled: it would strip the inline sport SVG.
  #showTooltip(cell) {
    if (!window.bootstrap?.Tooltip || !cell.dataset.tooltip) return

    let tooltip = this.tooltips.get(cell)
    if (!tooltip) {
      tooltip = new window.bootstrap.Tooltip(cell, {
        html: true,
        sanitize: false,
        trigger: "manual",
        container: "body",
        title: cell.dataset.tooltip
      })
      this.tooltips.set(cell, tooltip)
    }
    tooltip.show()
  }

  #hideTooltip(cell) {
    this.tooltips.get(cell)?.hide()
  }

  #disposeTooltips() {
    for (const tooltip of this.tooltips.values()) tooltip.dispose()
    this.tooltips.clear()
  }

  #showState(name) {
    for (const target of [ "loading", "empty", "error" ]) {
      this[`${target}Target`].hidden = target !== name
    }
  }
}

// Five-step ramp keyed to the viewer's own non-zero days: the busiest quarter
// reaches level 4 whatever the absolute values are.
function distanceThresholds(values) {
  const nonZero = values.filter((value) => value > 0).sort((a, b) => a - b)
  if (!nonZero.length) return [ 0, 0, 0 ]

  const at = (quantile) => nonZero[Math.min(nonZero.length - 1, Math.floor(quantile * nonZero.length))]
  return [ at(0.25), at(0.5), at(0.75) ]
}

function intensityLevel(value, [ q1, q2, q3 ]) {
  if (value <= 0) return 0
  if (q1 === q2 && q2 === q3) return 2
  if (value >= q3) return 4
  if (value >= q2) return 3
  if (value >= q1) return 2
  return 1
}

function startOfDay(date) {
  const copy = new Date(date)
  copy.setHours(0, 0, 0, 0)
  return copy
}

function addDays(date, days) {
  const copy = new Date(date)
  copy.setDate(copy.getDate() + days)
  return copy
}

function fromISODate(value) {
  const [ year, month, day ] = value.split("-").map(Number)
  return new Date(year, month - 1, day)
}

function toISODate(date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`
}

function weekStartOnOrBefore(date, weekStart) {
  // JS Sunday = 0 … Saturday = 6. Monday-start weeks begin on 1, Sunday-start on 0.
  const wantSunday = weekStart === "sunday"
  const day = date.getDay()
  const delta = wantSunday ? day : (day + 6) % 7
  return addDays(date, -delta)
}

function formatDistance(metres, unitSystem, locale) {
  const value = unitSystem === "imperial" ? metres / METRES_PER_MILE : metres / METRES_PER_KILOMETRE
  const unit = unitSystem === "imperial" ? "mi" : "km"
  return `${new Intl.NumberFormat(locale, { maximumFractionDigits: 1 }).format(value)} ${unit}`
}

// Mirrors the server's format_duration, so a tooltip and the tables below the
// charts never disagree about how a duration is written.
function formatDuration(seconds) {
  const total = Math.max(Math.round(seconds), 0)
  const hours = Math.floor(total / 3600)
  const minutes = Math.floor((total % 3600) / 60)
  const remainder = total % 60
  if (hours > 0) return `${hours}:${String(minutes).padStart(2, "0")}:${String(remainder).padStart(2, "0")}`
  return `${minutes}:${String(remainder).padStart(2, "0")}`
}
