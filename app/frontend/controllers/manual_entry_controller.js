import { Controller } from "@hotwired/stimulus";

// The manual entry form (docs/dev/MANUAL-ENTRY.md): the ascent hides for a
// sport that measures no elevation, and its input is disabled so it is never
// submitted. Without a sport, every field stays available.
export default class extends Controller {
  static targets = ["sport", "elevation"];

  connect() {
    this.sportChanged();
  }

  sportChanged() {
    if (!this.hasSportTarget) return;
    const option = this.sportTarget.selectedOptions[0];
    const chosen = option && option.value !== "";
    this.toggle(this.elevationTargets, !chosen || option.dataset.recordsElevation === "true");
  }

  toggle(groups, visible) {
    groups.forEach((group) => {
      group.hidden = !visible;
      group.querySelectorAll("input").forEach((input) => {
        input.disabled = !visible;
      });
    });
  }
}
