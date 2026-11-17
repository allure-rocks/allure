import { Controller } from "@hotwired/stimulus";

// Bulk selection on the workout table (DESIGN.md §10.19,
// docs/dev/BULK-ACTIONS.md).
//
// The bar and the checkboxes work without JavaScript: the form is plain, the
// row boxes are associated with `form=`, and CSS `:has()` reveals the bar.
// This controller adds the live count, the header tri-state, the filtered
// scope switch and the apply-button enablement.
export default class extends Controller {
  static targets = ["checkbox", "all", "scope", "countNumber", "countOne", "countOther", "apply"];
  static values = { filtered: Number };

  connect() {
    this.refresh();
  }

  // The endless scroll appends rows: under the filtered scope they arrive
  // selected, otherwise unselected, and the count and tri-state follow.
  checkboxTargetConnected(checkbox) {
    if (this.hasScopeTarget && this.scopeTarget.checked) checkbox.checked = true;
    this.refresh();
  }

  toggleAll() {
    const checked = this.hasAllTarget && this.allTarget.checked;
    this.checkboxTargets.forEach((checkbox) => {
      checkbox.checked = checked;
    });
    if (this.hasScopeTarget) this.scopeTarget.checked = false;
    this.refresh();
  }

  // Checking one row means the selection is those rows, not the whole
  // filtered set.
  rowChanged() {
    if (this.hasScopeTarget) this.scopeTarget.checked = false;
    this.refresh();
  }

  // The scope switch stands for the whole filtered set: show every rendered
  // row as selected so the count and the page agree.
  scopeChanged() {
    if (this.hasScopeTarget && this.scopeTarget.checked) {
      this.checkboxTargets.forEach((checkbox) => {
        checkbox.checked = true;
      });
    }
    this.refresh();
  }

  refresh() {
    const scope = this.hasScopeTarget && this.scopeTarget.checked;
    const checked = this.checkboxTargets.filter((checkbox) => checkbox.checked).length;
    const count = scope ? this.filteredValue : checked;

    if (this.hasCountNumberTarget) this.countNumberTarget.textContent = count;
    if (this.hasCountOneTarget) this.countOneTarget.hidden = count !== 1;
    if (this.hasCountOtherTarget) this.countOtherTarget.hidden = count === 1;
    if (this.hasApplyTarget) this.applyTarget.disabled = count === 0;

    this.element.classList.toggle("allure-table-card--selected", count > 0);

    if (this.hasAllTarget) {
      const pageCount = this.checkboxTargets.length;
      this.allTarget.checked = pageCount > 0 && checked === pageCount;
      this.allTarget.indeterminate = checked > 0 && checked < pageCount;
    }
  }
}
