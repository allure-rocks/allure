import { Controller } from "@hotwired/stimulus";

// A "show more" toggle for content the server renders in full: the CSS hides
// the target while it lacks `is-expanded` (often only below a breakpoint, so
// desktop keeps everything visible), and the button flips that class, its
// aria-expanded, and its label. Without JavaScript nothing is hidden: the
// collapsing classes only apply once this controller marks the element ready.
export default class extends Controller {
  static targets = ["button", "content", "label"];
  static values = { expandedLabel: String, collapsedLabel: String };

  connect() {
    this.element.classList.add("is-disclosure-ready");
    this.render(false);
  }

  disconnect() {
    this.element.classList.remove("is-disclosure-ready");
  }

  toggle() {
    this.render(!this.expanded);
  }

  render(expanded) {
    this.expanded = expanded;
    this.contentTargets.forEach((element) => element.classList.toggle("is-expanded", expanded));
    this.buttonTargets.forEach((element) => element.setAttribute("aria-expanded", expanded ? "true" : "false"));
    this.element.classList.toggle("is-expanded", expanded);
    const label = expanded ? this.expandedLabelValue : this.collapsedLabelValue;
    if (label) this.labelTargets.forEach((element) => { element.textContent = label; });
  }
}
