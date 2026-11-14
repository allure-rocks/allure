import { Controller } from "@hotwired/stimulus"

// Refresh only the processing gallery, never the upload picker. A Turbo frame
// replacement disconnects this timer and mounts another only if still pending;
// a morphing refresh keeps the controller, so every frame render republishes
// the placed photos and schedules the next poll from the frame's own state
// (a morph updates its children, never the frame's attributes). A refresh
// never interrupts an open viewer, an open row menu or a caption being typed.
export default class extends Controller {
  static values = { url: String }

  connect() { this.refresh() }
  disconnect() { window.clearTimeout(this.timer) }

  refresh() {
    window.dispatchEvent(new CustomEvent("allure:photos-changed", { detail: { markers: this.#markers() } }))
    this.schedule()
  }

  // An upload just finished: its tile is not in the frame yet, so refresh
  // once, as soon as the owner is not reading or typing in the gallery.
  uploaded() { this.#reloadWhenIdle(1000) }

  // A manual reorder marks the order as the owner's: the sort button and the
  // move actions come from the server.
  reordered() { this.uploaded() }

  schedule() {
    window.clearTimeout(this.timer)
    if (!this.#pending()) return
    this.timer = window.setTimeout(() => {
      if (this.#busy()) {
        this.schedule()
        return
      }
      this.#reloadFrame()
    }, 4000)
  }

  #pending() {
    return this.element.querySelector("[data-photo-gallery-pending]")?.dataset.photoGalleryPending === "true"
  }

  #markers() {
    const raw = this.element.querySelector("[data-photo-gallery-markers]")?.dataset.photoGalleryMarkers
    if (!raw) return []
    try {
      return JSON.parse(raw)
    } catch {
      return []
    }
  }

  #reloadWhenIdle(delay) {
    window.clearTimeout(this.timer)
    this.timer = window.setTimeout(() => {
      if (this.#busy()) {
        this.#reloadWhenIdle(delay)
        return
      }
      this.#reloadFrame()
    }, delay)
  }

  #busy() {
    const editing = this.element.contains(document.activeElement) && document.activeElement.matches("textarea, input")
    const viewing = this.element.querySelector("dialog[open]")
    // A morph would close an open row menu under the owner's pointer.
    const menu = this.element.querySelector(".dropdown-menu.show")
    return document.hidden || editing || viewing || menu
  }

  #reloadFrame() {
    const frame = this.element.closest("turbo-frame")
    if (!frame) return
    frame.src ? frame.reload() : frame.src = this.urlValue
  }
}
