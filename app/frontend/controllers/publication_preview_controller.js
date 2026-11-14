import { Controller } from "@hotwired/stimulus";

// What the selected profile shares (DESIGN.md §19.1).
//
// The publish form embeds per-profile readiness computed on page load: the
// shared and withheld field lists, the readiness warnings, the submit state,
// and the profile's default delay. A profile change only swaps that embedded
// data — no request, no projection of the workout.
export default class extends Controller {
  static targets = ["profile", "delay", "shared", "withheld", "withheldGroup", "warnings", "submit", "photoChoice", "photoOff"];

  static values = {
    readiness: Object,
    immediateLabel: String,
    delayedLabel: String,
  };

  connect() {
    this.render();
  }

  update() {
    this.render();
  }

  // The delay select changed without a profile switch: only the action label
  // follows.
  updateLabel() {
    this.setSubmitLabel();
  }

  render() {
    const status = this.readinessValue[this.profileTarget.value] || {};
    this.renderWarnings(status.warnings || []);
    if (Array.isArray(status.shared) && this.hasSharedTarget) {
      this.renderList(this.sharedTarget, status.shared, "ti-check text-success");
    }
    if (Array.isArray(status.withheld) && this.hasWithheldTarget) {
      this.renderList(this.withheldTarget, status.withheld, "ti-x text-secondary");
      if (this.hasWithheldGroupTarget) this.withheldGroupTarget.hidden = status.withheld.length === 0;
    }
    this.setSubmitDisabled(status.ready === false);
    this.setDelay(status.delay);
    this.setPhotoChoice(status.photos === true);
  }

  // A profile that shares no photos gets the sentence and the way to the
  // profiles, never a grid of ticks that would share nothing.
  setPhotoChoice(shared) {
    if (this.hasPhotoChoiceTarget) this.photoChoiceTarget.hidden = !shared;
    if (this.hasPhotoOffTarget) this.photoOffTarget.hidden = shared;
  }

  renderList(list, fields, iconClasses) {
    list.replaceChildren(
      ...fields.map((field) => {
        const item = document.createElement("li");
        const icon = document.createElement("i");
        icon.className = `ti ${iconClasses} me-1`;
        icon.setAttribute("aria-hidden", "true");
        item.append(icon, document.createTextNode(field));
        return item;
      }),
    );
  }

  // The delay is a per-profile default; the owner can still override it for
  // one publish with the same preset list. The submit label tells the truth:
  // "Publish" for an immediate publication, "Schedule publication" when a hold
  // is selected.
  setDelay(delay) {
    if (this.hasDelayTarget && typeof delay === "number") {
      this.delayTarget.value = String(delay);
    }
    this.setSubmitLabel();
  }

  setSubmitLabel() {
    if (!this.hasSubmitTarget) return;
    const immediate = this.hasDelayTarget && this.delayTarget.value === "0";
    const label = immediate ? this.immediateLabelValue : this.delayedLabelValue;
    if (label) this.submitTarget.value = label;
  }

  renderWarnings(warnings) {
    this.warningsTarget.replaceChildren(
      ...warnings.map((warning) => {
        const paragraph = document.createElement("p");
        paragraph.className = "mb-1";
        paragraph.textContent = warning;
        return paragraph;
      }),
    );
    this.warningsTarget.classList.toggle("visually-hidden", warnings.length === 0);
  }

  setSubmitDisabled(disabled) {
    if (!this.hasSubmitTarget) return;
    this.submitTarget.disabled = disabled;
    this.submitTarget.setAttribute("aria-disabled", disabled.toString());
  }
}
