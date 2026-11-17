import { Controller } from "@hotwired/stimulus"

// The demo strip's reset warning (docs/dev/DEMO.md). The server renders the
// next reset as an absolute instant; the controller turns the warning line on
// by itself when it comes within the window, without any reload — the page
// may have been open for hours by then, and Turbo keeps it alive.
export default class extends Controller {
  static values = { at: String, window: { type: Number, default: 0 } }
  static targets = ["warning"]

  connect() {
    this.tick()
    this.timer = setInterval(() => this.tick(), 10_000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  tick() {
    const remaining = Date.parse(this.atValue) - Date.now()
    this.warningTarget.classList.toggle("d-none", remaining > this.windowValue * 1000)
  }
}
