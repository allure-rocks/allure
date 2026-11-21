import { Controller } from "@hotwired/stimulus";

// What the selected profile shares (DESIGN.md §19.1).
//
// The publish form embeds per-profile readiness computed on page load: the
// shared and withheld field lists, the readiness warnings, the submit state,
// and the profile's default delay. A profile change only swaps that embedded
// data — no request, no projection of the workout.
export default class extends Controller {
  static targets = ["profile", "delay", "audience", "audienceRow", "lists", "shared", "withheld", "withheldGroup", "warnings", "submit", "photoChoice", "photoOff"];

  static values = {
    readiness: Object,
    immediateLabel: String,
    delayedLabel: String,
  };

  connect() {
    this.render();
  }

  update() {
    const delay = this.status.delay;
    if (typeof delay === "number") this.delayTarget.value = String(delay);
    this.render();
  }

  updateLabel() {
    this.setSubmitLabel();
    this.setSubmitDisabled(this.status.ready !== true || this.delayTarget.value === "");
  }

  get status() {
    return this.readinessValue[this.profileTarget.value] || {};
  }

  render() {
    const status = this.status;
    this.audienceTarget.textContent = status.audience || "";
    this.audienceRowTarget.hidden = !status.audience;
    this.listsTarget.hidden = !status.audience;
    this.renderWarnings(status.warnings || []);
    if (Array.isArray(status.shared) && this.hasSharedTarget) {
      this.renderList(this.sharedTarget, status.shared, "ti-check text-success");
    }
    if (Array.isArray(status.withheld) && this.hasWithheldTarget) {
      this.renderList(this.withheldTarget, status.withheld, "ti-x text-secondary");
      if (this.hasWithheldGroupTarget) this.withheldGroupTarget.hidden = status.withheld.length === 0;
    }
    this.updateLabel();
    if (this.hasPhotoChoiceTarget) this.photoChoiceTarget.hidden = status.photos !== true;
    if (this.hasPhotoOffTarget) this.photoOffTarget.hidden = !status.audience || status.photos === true;
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

  setSubmitLabel() {
    if (!this.hasSubmitTarget) return;
    const immediate = !this.delayTarget.value || this.delayTarget.value === "0";
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
