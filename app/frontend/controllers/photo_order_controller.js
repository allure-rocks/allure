import { Controller } from "@hotwired/stimulus"

// The manager's order (DESIGN.md §20.24): the handle arms the row, a drop
// shows where it lands, and the menu's move actions are the keyboard and
// touch path. Saving the whole order marks it as the owner's, which stops the
// automatic capture-time pass.
export default class extends Controller {
  static targets = ["list", "error"]
  static values = { url: String, error: String }

  connect() { this.abortController = new AbortController() }
  disconnect() { this.abortController.abort() }

  // A row is draggable only once its handle was pressed: a touch drag on the
  // page scrolls, and a drag started on a caption selects text.
  grab(event) {
    event.currentTarget.closest("[data-photo-id]").draggable = true
  }

  start(event) {
    if (this.saving) { event.preventDefault(); return }
    this.dragged = event.currentTarget
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.dragged.dataset.photoId)
  }

  over(event) {
    if (!this.dragged || this.dragged === event.currentTarget) return
    event.preventDefault()
    this.#clearMarks()
    const row = event.currentTarget
    const after = event.clientY > row.getBoundingClientRect().top + row.offsetHeight / 2
    row.classList.toggle("allure-photo-row--before", !after)
    row.classList.toggle("allure-photo-row--after", after)
  }

  end() {
    if (this.dragged) this.dragged.draggable = false
    this.dragged = null
    this.#clearMarks()
  }

  drop(event) {
    if (!this.dragged) return
    event.preventDefault()
    const row = event.currentTarget
    const after = event.clientY > row.getBoundingClientRect().top + row.offsetHeight / 2
    const previous = Array.from(this.listTarget.children)
    this.listTarget.insertBefore(this.dragged, after ? row.nextElementSibling : row)
    this.end()
    this.save(previous)
  }

  move(event) {
    if (this.saving) return
    const row = event.currentTarget.closest("[data-photo-id]")
    const direction = Number(event.currentTarget.dataset.direction)
    const sibling = direction < 0 ? row.previousElementSibling : row.nextElementSibling
    if (!sibling) return
    const previous = Array.from(this.listTarget.children)
    this.listTarget.insertBefore(direction < 0 ? row : sibling, direction < 0 ? sibling : row)
    this.save(previous).then(() => row.querySelector("[data-bs-toggle='dropdown']")?.focus())
  }

  async save(previous) {
    this.saving = true
    this.errorTarget.textContent = ""
    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        signal: this.abortController.signal,
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content ?? "",
        },
        body: JSON.stringify({ ids: Array.from(this.listTarget.children, (row) => row.dataset.photoId) }),
      })
      if (!response.ok) throw new Error("order")
      const rows = Array.from(this.listTarget.children)
      rows.forEach((row, index) => {
        row.querySelectorAll("[data-direction]").forEach((button) => {
          button.disabled = Number(button.dataset.direction) < 0 ? index === 0 : index === rows.length - 1
        })
      })
      window.dispatchEvent(new CustomEvent("allure:photos-reordered"))
    } catch (error) {
      if (error.name !== "AbortError") {
        previous.forEach((row) => this.listTarget.append(row))
        this.errorTarget.textContent = this.errorValue
      }
    } finally {
      this.saving = false
    }
  }

  #clearMarks() {
    this.listTarget.querySelectorAll(".allure-photo-row--before, .allure-photo-row--after").forEach((row) => {
      row.classList.remove("allure-photo-row--before", "allure-photo-row--after")
    })
  }
}
