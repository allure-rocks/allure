import { Controller } from "@hotwired/stimulus";

// A sport select-group that scrolls sideways on phones (DESIGN.md §10.6):
// bring the first checked pill into view without moving the page vertically.
// Shared by the workout list toolbar and the hub toolbar.
export default class extends Controller {
  connect() {
    const row = this.element;
    const checked = row.querySelector("input:checked");
    if (!checked || row.scrollWidth <= row.clientWidth) return;

    const item = checked.closest(".form-selectgroup-item");
    row.scrollLeft = Math.max(0, item.offsetLeft - row.offsetLeft - 16);
  }
}
