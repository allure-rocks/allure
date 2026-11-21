import { Controller } from "@hotwired/stimulus";

// Client-side tabs for the merged laps card. All panes are server-rendered;
// switching only toggles classes and hidden, then broadcasts the active pane's
// chart data (dashed boundaries and pictogram markers) so the elevation
// profile can redraw without a request. Accessible tablist semantics are
// maintained by hand.
//
// The card carries ten kinds of analysis; when they do not fit the card's
// width the tail folds behind a « Plus » menu (DESIGN.md §20.3). The line is
// measured on connect and on every resize, and the menu only ever lists the
// tabs that are actually hidden.
//
// The same card drives the cross-surface highlight: hovering, focusing, or
// pinning a row (tap/click) broadcasts its distance range so the chart shades
// the band and the map thickens the matching slice. A pinned row survives the
// pointer leaving; a hover or focus previews over it while active.
const TAB_CHANGED = "allure:analysis-tab-changed";
const ANALYSIS_HIGHLIGHT = "allure:analysis-highlight";
const FIT_TOLERANCE = 1;

export default class extends Controller {
  static targets = ["tab", "pane", "tablist", "item", "more", "moreButton", "moreBadge", "menuItem"];

  connect() {
    this.activeRow = null;
    this.pinnedRow = null;
    this.stepPreviewData = null;
    this.publishedKey = null;
    this.hiddenPanes = new Set();
    this.moreVisible = false;
    this.publishActive();

    // A `#workout-laps-<key>` fragment opens that tab, so the weather card can
    // link to its hourly table (DESIGN.md §20.3) and any tab can be shared.
    this.onHashChange = () => this.#openHashTarget();
    window.addEventListener("hashchange", this.onHashChange);

    this.#observeWidth();
    this.#layoutTabs();
    this.#openHashTarget();
  }

  disconnect() {
    window.removeEventListener("hashchange", this.onHashChange);
    this.resizeObserver?.disconnect();
    this.resizeObserver = null;
    if (this.hasTablistTarget) this.tablistTarget.classList.remove("allure-analysis-tabs--managed");
  }

  select(event) {
    this.#activate(event.currentTarget);
  }

  // A tab chosen from the « Plus » menu: it may stay in the menu, so the
  // toggle keeps carrying the active state and the focus.
  selectFromMenu(event) {
    const pane = event.currentTarget.dataset.pane;
    const tab = this.tabTargets.find((candidate) => candidate.dataset.pane === pane);
    if (!tab) return;

    this.#activate(tab);
    this.#closeMenu();
    const target = this.hiddenPanes.has(pane) ? this.moreButtonTarget : tab;
    target?.focus();
  }

  keydown(event) {
    if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
    const stops = this.#keyboardStops();
    const index = stops.indexOf(event.currentTarget);
    if (index === -1) return;
    event.preventDefault();

    let next;
    if (event.key === "Home") next = stops[0];
    else if (event.key === "End") next = stops.at(-1);
    else {
      const offset = event.key === "ArrowRight" ? 1 : -1;
      next = stops[(index + offset + stops.length) % stops.length];
    }
    if (!next || next === event.currentTarget) return;

    if (next === this.moreButtonTarget) {
      next.focus();
      return;
    }

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
    const tab = this.#selectedTab();
    this.#publish(this.#paneFor(tab));
  }

  // The tab line is measured against the card's own width, and the window is
  // not the only thing that moves it: the desktop split layout gives the card
  // a different column on resize, and the icon font settles after connect.
  #observeWidth() {
    if (!this.hasTablistTarget) return;

    this.tablistTarget.classList.add("allure-analysis-tabs--managed");
    this.resizeObserver = new ResizeObserver(() => this.#layoutTabs());
    this.resizeObserver.observe(this.tablistTarget);
    document.fonts?.ready.then(() => {
      if (this.element.isConnected) this.#layoutTabs();
    });
  }

  // Show every tab, then fold the ones that do not fit, in reading order, into
  // the « Plus » menu.
  #layoutTabs() {
    if (!this.hasTablistTarget || !this.hasItemTarget) return;
    const list = this.tablistTarget;

    for (const item of this.itemTargets) item.classList.remove("d-none");
    if (this.hasMoreTarget) this.moreTarget.classList.add("d-none");
    this.moreVisible = false;

    if (list.scrollWidth <= list.clientWidth + FIT_TOLERANCE) {
      this.#syncMore();
      return;
    }
    if (!this.hasMoreTarget) return;

    this.moreTarget.classList.remove("d-none");
    this.moreVisible = true;
    const budget = list.clientWidth - this.moreTarget.offsetWidth;

    let used = 0;
    for (const item of this.itemTargets) {
      if (used + item.offsetWidth <= budget) {
        used += item.offsetWidth;
        continue;
      }
      item.classList.add("d-none");
    }
    this.#syncMore();
  }

  // The menu lists exactly the hidden tabs, and its entry for the active one
  // is marked when that tab had to fold.
  #syncMore() {
    const hidden = new Set(
      this.itemTargets
        .filter((item) => item.classList.contains("d-none"))
        .map((item) => item.querySelector("[data-pane]")?.dataset.pane)
        .filter(Boolean)
    );
    this.hiddenPanes = hidden;

    if (this.hasMenuItemTarget) {
      const selected = this.#selectedTab()?.dataset.pane;
      for (const item of this.menuItemTargets) {
        item.classList.toggle("d-none", !hidden.has(item.dataset.pane));
        const active = item.dataset.pane === selected;
        item.classList.toggle("active", active);
        if (active) item.setAttribute("aria-current", "true");
        else item.removeAttribute("aria-current");
      }
    }

    this.#renderToggle();
    this.#updateRovingStops();
  }

  // The toggle says what it holds: « Plus » and the folded count. A folded
  // active tab keeps the line readable through the toggle's active state, but
  // never through its label — a tab name would outgrow a phone's line
  // (DESIGN.md §20.3).
  #renderToggle() {
    if (!this.moreVisible) return;

    if (this.hasMoreBadgeTarget) {
      this.moreBadgeTarget.classList.remove("d-none");
      this.moreBadgeTarget.textContent = this.hiddenPanes.size;
    }
  }

  // One tab stop for the whole line: the selected tab when it is visible,
  // otherwise the « Plus » toggle that now carries it.
  #updateRovingStops() {
    const selected = this.#selectedTab();
    const selectedHidden = Boolean(selected && this.hiddenPanes.has(selected.dataset.pane));

    for (const tab of this.tabTargets) {
      tab.tabIndex = tab === selected && !selectedHidden ? 0 : -1;
    }
    if (this.hasMoreButtonTarget) {
      this.moreButtonTarget.tabIndex = selectedHidden ? 0 : -1;
      this.moreButtonTarget.classList.toggle("active", selectedHidden);
    }
  }

  #selectedTab() {
    return this.tabTargets.find((tab) => tab.getAttribute("aria-selected") === "true");
  }

  #visibleTabs() {
    return this.tabTargets.filter((tab) => !this.hiddenPanes.has(tab.dataset.pane));
  }

  // Arrow keys walk the visible tabs and end on « Plus » when it is shown.
  #keyboardStops() {
    const stops = this.#visibleTabs();
    return this.moreVisible && this.hasMoreButtonTarget ? [ ...stops, this.moreButtonTarget ] : stops;
  }

  // A fragment naming one of this card's panes opens that tab and brings the
  // card into view: the pane is hidden until then, so the browser's own jump has
  // nothing to land on (DESIGN.md §20.3).
  #openHashTarget() {
    const id = window.location.hash.replace(/^#/, "");
    if (!id) return;
    const tab = this.tabTargets.find((candidate) => candidate.dataset.pane === id);
    if (!tab) return;

    if (tab.getAttribute("aria-selected") !== "true") this.#activate(tab);

    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const section = this.element.closest(".allure-detail-section") ?? this.element;
    section.scrollIntoView({ behavior: reduced ? "auto" : "smooth", block: "start" });
    // The browser's own fragment handling runs after this event and would drop
    // the focus we set here, so the tab takes it on the next frame — or the
    // toggle, when the tab folded into the menu.
    requestAnimationFrame(() => {
      const target = this.hiddenPanes.has(tab.dataset.pane) ? this.moreButtonTarget : tab;
      target?.focus({ preventScroll: true });
    });
  }

  #activate(tab) {
    for (const candidate of this.tabTargets) {
      const selected = candidate === tab;
      candidate.classList.toggle("active", selected);
      candidate.setAttribute("aria-selected", selected ? "true" : "false");
    }
    for (const pane of this.paneTargets) {
      const selected = pane.id === tab.dataset.pane;
      pane.classList.toggle("show", selected);
      pane.classList.toggle("active", selected);
      pane.hidden = !selected;
    }

    // A highlight that belongs to the pane being left would keep drawing a band
    // and a map slice for a row the reader can no longer see.
    const pane = this.#paneFor(tab);
    this.stepPreviewData = null;
    if (this.activeRow && !pane?.contains(this.activeRow)) this.#setActiveRow(null);
    if (this.pinnedRow && !pane?.contains(this.pinnedRow)) this.#setPinnedRow(null);

    this.#syncMore();
    this.#publish(pane);
  }

  #closeMenu() {
    if (!this.hasMoreButtonTarget) return;
    window.bootstrap?.Dropdown.getOrCreateInstance(this.moreButtonTarget).hide();
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
