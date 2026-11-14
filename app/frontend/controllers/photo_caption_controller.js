import { Controller } from "@hotwired/stimulus"

// The caption saves itself (DESIGN.md §20.24): leaving the field, or Enter,
// sends it; Shift+Enter keeps a line break. The row's thumbnail and alt text
// follow at once, and a refusal leaves the text in place, marked invalid.
export default class extends Controller {
  static targets = ["field", "status"]
  static values = { url: String, saved: String, error: String }

  connect() { this.initial = this.fieldTarget.value }
  disconnect() { this.abortController?.abort() }

  keydown(event) {
    if (event.key !== "Enter" || event.shiftKey) return
    event.preventDefault()
    this.fieldTarget.blur()
  }

  async save() {
    const caption = this.fieldTarget.value
    if (caption === this.initial) return

    this.abortController?.abort()
    this.abortController = new AbortController()
    this.fieldTarget.classList.remove("is-invalid")
    this.statusTarget.textContent = ""
    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        signal: this.abortController.signal,
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content ?? "",
        },
        body: JSON.stringify({ photo: { caption } }),
      })
      if (!response.ok) throw new Error("caption")
      const data = await response.json()
      this.initial = caption
      this.statusTarget.textContent = this.savedValue
      this.#updateLabel(data.label)
    } catch (error) {
      if (error.name === "AbortError") return
      this.fieldTarget.classList.add("is-invalid")
      this.statusTarget.textContent = this.errorValue
    }
  }

  #updateLabel(label) {
    const preview = this.element.closest("[data-photo-id]")?.querySelector("[data-photo-lightbox-target='photo']")
    if (!preview) return
    preview.dataset.caption = label
    const image = preview.querySelector("img")
    if (image) image.alt = label
  }
}
