import { Controller } from "@hotwired/stimulus";

// Client-side tabs for the merged laps card. All panes are server-rendered;
// switching only toggles classes and hidden, then broadcasts the active pane's
// chart data (dashed boundaries and pictogram markers) so the elevation
// profile can redraw without a request. Accessible tablist semantics are
// maintained by hand.
//
// The same card drives the cross-surface highlight: hovering, focusing, or
// pinning a row (tap/click) broadcasts its distance range so the chart shades
// the band and the map thickens the matching slice. A pinned row survives the
// pointer leaving; a hover or focus previews over it while active.
const TAB_CHANGED = "allure:analysis-tab-changed";
const ANALYSIS_HIGHLIGHT = "allure:analysis-highlight";

export default class extends Controller {
  static targets = ["tab", "pane", "tablist"];

  connect() {
    this.activeRow = null;
    this.pinnedRow = null;
    this.stepPreviewData = null;
    this.publishedKey = null;
    this.publishActive();
  }

  select(event) {
    this.#activate(event.currentTarget);
  }

  keydown(event) {
    if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
    event.preventDefault();

    const tabs = this.tabTargets;
    const index = tabs.indexOf(event.currentTarget);
    let next;
    if (event.key === "Home") next = tabs[0];
    else if (event.key === "End") next = tabs.at(-1);
    else {
      const offset = event.key === "ArrowRight" ? 1 : -1;
      next = tabs[(index + offset + tabs.length) % tabs.length];
    }
    if (!next) return;

    this.#activate(next);
    next.focus();
  }

  rowOver(event) {
    const row = event.target.closest("[data-analysis-range]");
    if (!row) return;
    if (row.contains(event.relatedTarget)) return;

    this.#setActiveRow(row);
  }

  rowOut(event) {
    const row = event.target.closest("[data-analysis-range]");
    if (!row) return;
    if (row.contains(event.relatedTarget)) return;
    // Moving straight to another row is a switch, not a clear: the matching
    // rowOver follows and publishes once.
    if (event.relatedTarget?.closest?.("[data-analysis-range]")) return;
    if (this.activeRow === row) this.#setActiveRow(null);
  }

  rowClick(event) {
    if (event.target.closest("a, button")) return;

    const row = event.target.closest("[data-analysis-range]");
    if (!row) return;

    if (this.pinnedRow === row) {
      // Unpin fully: a previous tap also emulated a mouseover, and the row is
      // focused, so both the preview and the focus state have to go.
      this.#setActiveRow(null);
      this.#setPinnedRow(null);
      row.blur();
    } else {
      this.#setPinnedRow(row);
    }
  }

  escape() {
    const row = this.activeRow ?? this.pinnedRow;
    this.#setActiveRow(null);
    this.#setPinnedRow(null);
    // Focus alone would keep previewing the range; Escape clears it all.
    row?.blur();
  }

  // The chart's route steps preview through this controller, so leaving a step
  // falls back to the pinned row instead of clearing the highlight.
  previewStep(event) {
    const detail = event.detail;
    this.stepPreviewData = detail?.clear || !Number.isFinite(Number(detail?.startDistance))
      ? null
      : detail;
    this.#syncHighlight();
  }

  publishActive() {
    const tab = this.tabTargets.find((candidate) => candidate.getAttribute("aria-selected") === "true");
    this.#publish(this.#paneFor(tab));
  }

  #activate(tab) {
    for (const candidate of this.tabTargets) {
      const selected = candidate === tab;
      candidate.classList.toggle("active", selected);
      candidate.setAttribute("aria-selected", selected ? "true" : "false");
      candidate.tabIndex = selected ? 0 : -1;
    }
    for (const pane of this.paneTargets) {
      const selected = pane.id === tab.dataset.pane;
      pane.classList.toggle("show", selected);
      pane.classList.toggle("active", selected);
      pane.hidden = !selected;
    }

    // A tab picked from the scrolled tab line slides fully into view.
    const smooth = !window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (this.hasTablistTarget) {
      const list = this.tablistTarget;
      const left = tab.getBoundingClientRect().left - list.getBoundingClientRect().left + list.scrollLeft;
      const right = left + tab.offsetWidth;
      if (left < list.scrollLeft || right > list.scrollLeft + list.clientWidth) {
        list.scrollTo({ left: Math.max(0, left - 16), behavior: smooth ? "smooth" : "auto" });
      }
    }

    // A highlight that belongs to the pane being left would keep drawing a band
    // and a map slice for a row the reader can no longer see.
    const pane = this.#paneFor(tab);
    this.stepPreviewData = null;
    if (this.activeRow && !pane?.contains(this.activeRow)) this.#setActiveRow(null);
    if (this.pinnedRow && !pane?.contains(this.pinnedRow)) this.#setPinnedRow(null);

    this.#publish(pane);
  }

  #setActiveRow(row) {
    if (this.activeRow === row) return;

    this.stepPreviewData = null;
    this.activeRow = row;
    this.#syncHighlight();
  }

  #setPinnedRow(row) {
    if (this.pinnedRow === row) return;

    this.stepPreviewData = null;
    this.pinnedRow?.classList.remove("table-active", "active");
    this.pinnedRow = row;
    this.pinnedRow?.classList.add("table-active", "active");
    this.#syncHighlight();
  }

  #syncHighlight() {
    const preview = this.stepPreviewData;
    const row = preview ? null : (this.activeRow ?? this.pinnedRow);
    const start = preview ? Number(preview.startDistance) : row ? Number(row.dataset.startDistance) : null;
    const end = preview ? Number(preview.endDistance) : row ? Number(row.dataset.endDistance) : null;
    const source = preview ? (preview.source ?? null) : (row?.dataset?.analysisSource || null);
    const label = preview ? (preview.label ?? null) : (row?.dataset?.analysisLabel || null);
    // A heart-rate zone is ridden in many places: its row carries every
    // stretch, which the profile and the map shade together.
    const ranges = preview ? null : this.#ranges(row);
    const key = start !== null && end !== null && Number.isFinite(start) && Number.isFinite(end)
      ? `${start}-${end}-${source}-${label}`
      : null;
    if (key === this.publishedKey) return;

    this.publishedKey = key;
    const detail = { startDistance: start, endDistance: end, source, label };
    if (ranges) detail.ranges = ranges;
    window.dispatchEvent(new CustomEvent(ANALYSIS_HIGHLIGHT, { detail: key ? detail : { clear: true } }));
  }

  #ranges(row) {
    const raw = row?.dataset?.analysisRanges;
    if (!raw) return null;
    try {
      const parsed = JSON.parse(raw);
      const ranges = Array.isArray(parsed)
        ? parsed.map(([start, end]) => ({ start: Number(start), end: Number(end) }))
          .filter(({ start, end }) => Number.isFinite(start) && Number.isFinite(end) && end > start)
        : [];
      return ranges.length ? ranges : null;
    } catch {
      return null;
    }
  }

  #paneFor(tab) {
    return this.paneTargets.find((pane) => pane.id === tab?.dataset?.pane);
  }

  #publish(pane) {
    window.dispatchEvent(new CustomEvent(TAB_CHANGED, {
      detail: {
        id: pane?.id ?? null,
        boundaries: this.#entries(pane, "boundaries"),
        markers: this.#entries(pane, "markers"),
        steps: this.#entries(pane, "analysisSteps"),
      },
    }));
  }

  #entries(pane, key) {
    const raw = pane?.dataset?.[key];
    if (!raw) return [];
    try {
      const parsed = JSON.parse(raw);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  }
}
