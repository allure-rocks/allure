import { Controller } from "@hotwired/stimulus";

// Moves focus into a reply composer as soon as its collapse opens
// (DESIGN.md §10.20). Bootstrap owns the collapse; the `shown.bs.collapse`
// binding lives in the element's data-action, so Stimulus releases it on
// disconnect and nothing outlives a Turbo render.
export default class extends Controller {
  static targets = ["field"];

  focus() {
    if (this.hasFieldTarget) this.fieldTarget.focus();
  }
}
