import { Controller } from "@hotwired/stimulus"

// Password reveal toggle. The button is the single source of state: it carries
// aria-pressed plus the action's accessible name and tooltip, so a screen
// reader announces what the next activation will do rather than only the
// current type. A live Bootstrap tooltip is refreshed with the new label, and
// the shared tooltip controller reads data-bs-title on every reconnect.
export default class extends Controller {
  static targets = [ "input", "button", "icon" ]
  static values = { showLabel: String, hideLabel: String }

  toggle() {
    const hidden = this.inputTarget.type === "password"
    this.inputTarget.type = hidden ? "text" : "password"
    this.buttonTarget.setAttribute("aria-pressed", String(hidden))
    const label = hidden ? this.hideLabelValue : this.showLabelValue
    this.buttonTarget.setAttribute("aria-label", label)
    this.buttonTarget.setAttribute("data-bs-title", label)
    window.bootstrap.Tooltip.getInstance(this.buttonTarget)?.setContent({ ".tooltip-inner": label })
    this.iconTarget.classList.toggle("ti-eye", !hidden)
    this.iconTarget.classList.toggle("ti-eye-off", hidden)
  }
}
