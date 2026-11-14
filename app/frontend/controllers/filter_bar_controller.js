import { Controller } from "@hotwired/stimulus";

// Workout list toolbar (DESIGN.md §10.6, §13). The sport pills, the period
// and the sort apply on change. The drawer's own filters apply together with
// its « Afficher les résultats » button, so choosing several of them never
// reloads the page under the open sheet. Without JavaScript the drawer is an
// ordinary block of the same GET form and its button submits everything.
//
// The date fields only apply to the custom period: they are disabled — and
// so absent from the query string — while a preset is chosen. Choosing
// « Personnalisée » opens the drawer on the dates instead of submitting.
export default class extends Controller {
  static targets = ["form", "period", "date", "range", "sheet"];

  connect() {
    this.appliedPeriod = this.hasPeriodTarget ? this.periodTarget.value : null;
    this.syncDates();
    this.beforeCache = () => this.closeSheet();
    this.sheetHidden = () => this.restorePeriod();
    document.addEventListener("turbo:before-cache", this.beforeCache);
    if (this.hasSheetTarget) this.sheetTarget.addEventListener("hidden.bs.offcanvas", this.sheetHidden);
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.beforeCache);
    if (this.hasSheetTarget) this.sheetTarget.removeEventListener("hidden.bs.offcanvas", this.sheetHidden);
  }

  // A drawer closed without applying leaves the period the list shows: a
  // custom range chosen and then abandoned must not linger in the select.
  restorePeriod() {
    if (!this.hasPeriodTarget || this.appliedPeriod === null) return;

    this.periodTarget.value = this.appliedPeriod;
    this.syncDates();
  }

  submit() {
    this.syncDates();
    this.formTarget.requestSubmit();
  }

  period() {
    this.syncDates();
    if (this.periodTarget.value !== "custom") {
      this.formTarget.requestSubmit();
      return;
    }

    const sheet = this.sheet();
    if (!sheet) return;
    this.sheetTarget.addEventListener("shown.bs.offcanvas", () => this.dateTargets[0]?.focus(), { once: true });
    sheet.show();
  }

  syncDates() {
    if (!this.hasPeriodTarget) return;

    const custom = this.periodTarget.value === "custom";
    this.dateTargets.forEach((input) => {
      input.disabled = !custom;
    });
    if (this.hasRangeTarget) this.rangeTarget.hidden = !custom;
  }

  // Turbo snapshots the page before leaving it: a sheet left open would come
  // back from the cache without its backdrop.
  closeSheet() {
    if (!this.hasSheetTarget) return;

    window.bootstrap?.Offcanvas.getInstance(this.sheetTarget)?.dispose();
    this.sheetTarget.classList.remove("show", "showing", "hiding");
    this.sheetTarget.removeAttribute("aria-modal");
    this.sheetTarget.removeAttribute("role");
    document.querySelectorAll(".offcanvas-backdrop").forEach((node) => node.remove());
    document.body.style.removeProperty("overflow");
    document.body.style.removeProperty("padding-right");
  }

  sheet() {
    if (!this.hasSheetTarget || !window.bootstrap?.Offcanvas) return null;
    return window.bootstrap.Offcanvas.getOrCreateInstance(this.sheetTarget);
  }
}
