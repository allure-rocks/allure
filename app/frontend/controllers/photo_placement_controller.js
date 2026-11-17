import { Controller } from "@hotwired/stimulus"

// The owner drops a photo on the track (docs/dev/PHOTOS.md): « Placer sur le
// parcours » arms the map, which carries the instruction and its error itself
// (DESIGN.md §10.22). Its next click comes back as `allure:photo-placed`, sent
// to the server to be snapped onto the line; a refused click re-arms the map
// with the reason. The gallery frame then reloads and republishes the markers.
export default class extends Controller {
  static values = { prompt: String, error: String }

  connect() { this.abortController = new AbortController() }

  disconnect() {
    this.abortController.abort()
    if (this.pending) window.dispatchEvent(new CustomEvent("allure:photo-placed", { detail: { id: this.pending.id, cancelled: true } }))
    this.pending = null
  }

  start({ params: { id, url, label } }) {
    const prompt = this.promptValue.replace("%{photo}", label)
    this.pending = { id, url, prompt }
    this.#revealMap()
    window.dispatchEvent(new CustomEvent("allure:photo-place", { detail: { id, prompt } }))
  }

  async placed(event) {
    const detail = event.detail ?? {}
    if (!this.pending || detail.id !== this.pending.id) return
    if (detail.cancelled) {
      this.pending = null
      this.#backToRow(detail.id)
      return
    }

    const { url, prompt } = this.pending
    try {
      const response = await fetch(url, {
        method: "PATCH",
        signal: this.abortController.signal,
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content ?? "",
        },
        body: JSON.stringify({ mode: "manual", longitude: detail.longitude, latitude: detail.latitude }),
      })
      if (!response.ok) {
        let message = this.errorValue
        try { message = (await response.json()).error || message } catch { /* Non-JSON error page. */ }
        // The map stays armed: the owner clicked beside the line, not away
        // from the task.
        window.dispatchEvent(new CustomEvent("allure:photo-place-error", { detail: { id: detail.id, message, prompt } }))
        return
      }
      this.pending = null
      this.#backToRow(detail.id)
      const frame = this.element.closest("turbo-frame")
      if (frame) frame.src ? frame.reload() : frame.src = this.element.dataset.photoGalleryUrlValue
    } catch (error) {
      if (error.name !== "AbortError") {
        window.dispatchEvent(new CustomEvent("allure:photo-place-error", { detail: { id: detail.id, message: this.errorValue, prompt } }))
      }
    }
  }

  // On a phone the map is above the list: once the click is answered, or
  // cancelled, the row the owner started from comes back into view.
  #backToRow(id) {
    window.dispatchEvent(new CustomEvent("allure:photo-reveal", { detail: { id } }))
  }

  #revealMap() {
    const map = document.getElementById("section-map")
    if (!map) return
    const rect = map.getBoundingClientRect()
    if (rect.top >= 0 && rect.bottom <= window.innerHeight) return

    map.scrollIntoView({ behavior: "smooth", block: "center" })
  }
}
