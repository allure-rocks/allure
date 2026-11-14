import { Controller } from "@hotwired/stimulus"

// The photo viewer (DESIGN.md §10.22): the image, its caption, its place in
// the set and — when the gallery has them — the capture time, the distance
// along the route and the way back to the map. Escape and the backdrop close
// it natively; focus returns to the opener.
export default class extends Controller {
  static targets = ["dialog", "image", "caption", "counter", "meta", "map", "edit", "original", "photo"]

  disconnect() {
    if (this.dialogTarget.open) this.dialogTarget.close()
    this.imageTarget.removeAttribute("src")
  }

  open(event) {
    this.index = this.photoTargets.indexOf(event.currentTarget)
    this.render()
    this.dialogTarget.showModal()
  }

  // A photo marker on the map or a pill on the profile names the photo.
  openById(event) {
    const index = this.photoTargets.findIndex((photo) => photo.dataset.photoId === event.detail?.id)
    if (index === -1) return
    this.index = index
    this.render()
    if (!this.dialogTarget.open) this.dialogTarget.showModal()
  }

  close() { if (this.dialogTarget.open) this.dialogTarget.close() }

  previous() { this.#move(-1) }
  next() { this.#move(1) }

  key(event) {
    if (event.key === "ArrowLeft") { event.preventDefault(); this.previous() }
    if (event.key === "ArrowRight") { event.preventDefault(); this.next() }
  }

  touchStart(event) { this.touchX = event.changedTouches[0].clientX }

  touchEnd(event) {
    const delta = event.changedTouches[0].clientX - this.touchX
    if (Math.abs(delta) > 60) delta > 0 ? this.previous() : this.next()
  }

  // The marker is the same photo: close the viewer and let the map fly to it,
  // where the owner can move it and a reader can read it in place.
  showOnMap() {
    const photo = this.photoTargets[this.index]
    if (!photo) return
    this.close()
    window.dispatchEvent(new CustomEvent("allure:photo-focus", { detail: { id: photo.dataset.photoId } }))
  }

  #move(step) {
    this.index = (this.index + step + this.photoTargets.length) % this.photoTargets.length
    this.render()
  }

  render() {
    const photo = this.photoTargets[this.index]
    if (!photo) return
    this.imageTarget.src = photo.dataset.src
    this.imageTarget.alt = photo.dataset.caption
    this.captionTarget.textContent = photo.dataset.caption
    if (this.hasCounterTarget) this.counterTarget.textContent = `${this.index + 1} / ${this.photoTargets.length}`
    if (this.hasMetaTarget) {
      const meta = photo.dataset.meta ?? ""
      this.metaTarget.textContent = meta
      this.metaTarget.hidden = meta.length === 0
    }
    if (this.hasMapTarget) this.mapTarget.hidden = photo.dataset.map !== "1"
    if (this.hasEditTarget) {
      const edit = photo.dataset.edit
      this.editTarget.hidden = !edit
      if (edit) this.editTarget.href = edit
    }
    // A reader's gallery has no original to download.
    if (this.hasOriginalTarget) {
      this.originalTarget.href = photo.dataset.original
      this.originalTarget.setAttribute("data-bridge--download-url-value", photo.dataset.original)
    }
  }
}
