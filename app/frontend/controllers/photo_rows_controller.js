import { Controller } from "@hotwired/stimulus"

// The manager's map and list are two views of one set (DESIGN.md §20.24): a
// marker click brings its row into view, and a placement or its cancel comes
// back to the row it started from.
export default class extends Controller {
  focusRow(event) {
    const row = this.#row(event.detail?.id)
    if (row) this.#reveal(row, { center: true })
  }

  reveal(event) {
    const id = event.detail?.id
    if (!id) return
    this.revealId = id
    const row = this.#row(id)
    if (row) this.#reveal(row, { center: false })
  }

  // A placement reloads the list; the row it started from is revealed once
  // the new rows exist.
  rendered() {
    if (!this.revealId) return
    const row = this.#row(this.revealId)
    this.revealId = null
    if (row) this.#reveal(row, { center: false })
  }

  #row(id) {
    if (typeof id !== "string") return null
    return this.element.querySelector(`[data-photo-id="${CSS.escape(id)}"]`)
  }

  #reveal(row, { center }) {
    row.scrollIntoView({ behavior: "smooth", block: center ? "center" : "nearest" })
    row.classList.add("allure-photo-row--active")
    window.clearTimeout(this.timer)
    this.timer = window.setTimeout(() => row.classList.remove("allure-photo-row--active"), 2000)
    row.querySelector("[data-photo-lightbox-target='photo'], [data-action='photo-placement#start']")?.focus({ preventScroll: true })
  }
}
