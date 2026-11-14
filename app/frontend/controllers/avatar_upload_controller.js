import { Controller } from "@hotwired/stimulus"
import { layout, maxZoom, panBy, placement, zoomAround } from "../lib/avatar_crop"

// Avatar upload, crop stage and generated-avatar shuffle (DESIGN.md §9.4): a
// local preview before submit, the square the server keeps chosen on the
// image, the limits stated on the page, and a control that rotates the
// persisted seed through an inline fragment swap. The file never leaves the
// browser until submit; object URLs are revoked on every change and the
// shuffle request is aborted on Turbo disconnect.
export default class extends Controller {
  static targets = [
    "preview", "input", "error", "regenerateButton",
    "crop", "stage", "cropImage", "zoom",
    "cropX", "cropY", "cropSize", "cropWidth", "cropHeight"
  ]

  static values = {
    maxBytes: Number,
    maxDimension: Number,
    allowedTypes: Array,
    avatarClass: String,
    regenerateUrl: String,
    unsupportedTypeMessage: String,
    tooLargeMessage: String,
    tooLargeDimensionsMessage: String,
    unreadableMessage: String
  }

  connect() {
    this.abortController = new AbortController()
    this.pointers = new Map()
    this.originalPreview = this.previewTarget.innerHTML
    this.stageTarget.addEventListener("wheel", this.wheel, { passive: false })
    this.resizeObserver = new ResizeObserver(() => this.render())
    this.resizeObserver.observe(this.stageTarget)
  }

  disconnect() {
    this.abortController?.abort()
    this.resizeObserver?.disconnect()
    this.stageTarget.removeEventListener("wheel", this.wheel)
    this.release()
  }

  // Turbo keeps the page in its cache: a crop built from a file the restored
  // form no longer carries would be a lie.
  beforeCache() {
    this.inputTarget.value = ""
    this.clearCrop()
  }

  preview() {
    const file = this.inputTarget.files[0]
    this.inputTarget.setCustomValidity("")
    this.errorTarget.textContent = ""
    if (!file) return this.clearCrop()

    if (this.allowedTypesValue.length && !this.allowedTypesValue.includes(file.type)) {
      return this.reject(this.unsupportedTypeMessageValue)
    }
    if (this.maxBytesValue > 0 && file.size > this.maxBytesValue) {
      return this.reject(this.tooLargeMessageValue)
    }

    this.release()
    this.objectUrl = URL.createObjectURL(file)
    this.load()
  }

  async regenerate() {
    this.regenerateButtonTarget.disabled = true
    try {
      const response = await fetch(this.regenerateUrlValue, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content ?? "",
          Accept: "text/html"
        },
        signal: this.abortController.signal
      })
      if (!response.ok) return

      this.previewTarget.innerHTML = await response.text()
      this.originalPreview = this.previewTarget.innerHTML
      this.clearSelection()
    } catch {
      // A failed shuffle keeps the current avatar and the picked file.
    } finally {
      this.regenerateButtonTarget.disabled = false
    }
  }

  clearSelection() {
    this.inputTarget.value = ""
    this.inputTarget.setCustomValidity("")
    this.errorTarget.textContent = ""
    this.clearCrop()
  }

  reject(message) {
    this.inputTarget.setCustomValidity(message)
    this.errorTarget.textContent = message
    this.clearCrop()
  }

  // The picked file is measured by the browser, which applies the EXIF
  // orientation: the square it sends is in the pixels the server decodes.
  load() {
    const probe = new Image()
    this.probe = probe
    probe.onload = () => {
      if (this.probe !== probe) return
      this.probe = null
      if (this.maxDimensionValue > 0 && Math.max(probe.naturalWidth, probe.naturalHeight) > this.maxDimensionValue) {
        return this.reject(this.tooLargeDimensionsMessageValue)
      }
      this.photo = { width: probe.naturalWidth, height: probe.naturalHeight }
      this.zoomLevel = 1
      this.centre = { x: this.photo.width / 2, y: this.photo.height / 2 }
      this.cropImageTarget.src = this.objectUrl
      this.cropImageTarget.alt = ""
      this.cropTarget.hidden = false
      this.previewTarget.replaceChildren(this.#previewElement())
      this.render()
    }
    probe.onerror = () => {
      if (this.probe !== probe) return
      this.probe = null
      this.reject(this.unreadableMessageValue)
    }
    probe.src = this.objectUrl
  }

  render() {
    if (!this.photo || this.cropTarget.hidden) return
    const stageSize = this.stageTarget.clientWidth
    if (!stageSize) return

    const view = layout({ ...this.photo, zoom: this.zoomLevel, centreX: this.centre.x, centreY: this.centre.y, stageSize })
    this.cropImageTarget.style.width = `${view.width}px`
    this.cropImageTarget.style.height = `${view.height}px`
    this.cropImageTarget.style.transform = `translate(${view.left}px, ${view.top}px)`
    this.#renderPreview(view)
    this.#renderZoom()
    this.#write(view.rect)
  }

  dragStart(event) {
    if (event.pointerType === "mouse" && event.button !== 0) return
    this.stageTarget.focus({ preventScroll: true })
    this.stageTarget.setPointerCapture?.(event.pointerId)
    this.pointers.set(event.pointerId, { x: event.clientX, y: event.clientY })
    if (this.pointers.size === 1) {
      this.lastPoint = { x: event.clientX, y: event.clientY }
    } else if (this.pointers.size === 2) {
      this.pinch = this.#pinch()
    }
    this.stageTarget.classList.add("is-dragging")
    event.preventDefault()
  }

  dragMove(event) {
    if (!this.pointers.has(event.pointerId)) return
    this.pointers.set(event.pointerId, { x: event.clientX, y: event.clientY })

    if (this.pointers.size === 2 && this.pinch) {
      this.#pinchMove()
    } else if (this.pointers.size === 1 && this.lastPoint) {
      const dx = event.clientX - this.lastPoint.x
      const dy = event.clientY - this.lastPoint.y
      this.lastPoint = { x: event.clientX, y: event.clientY }
      this.#pan(dx, dy)
    }
  }

  dragEnd(event) {
    this.pointers.delete(event.pointerId)
    if (this.stageTarget.hasPointerCapture?.(event.pointerId)) this.stageTarget.releasePointerCapture(event.pointerId)
    this.pinch = null
    if (this.pointers.size === 0) {
      this.lastPoint = null
      this.stageTarget.classList.remove("is-dragging")
    } else {
      this.lastPoint = { ...this.pointers.values().next().value }
    }
  }

  wheel(event) {
    if (!this.photo) return
    event.preventDefault()
    const rect = this.stageTarget.getBoundingClientRect()
    this.#zoomTo(this.zoomLevel * Math.exp(-event.deltaY * 0.0015), event.clientX - rect.left, event.clientY - rect.top)
  }

  zoom() {
    if (!this.photo) return
    const max = maxZoom(this.photo)
    const ratio = Number(this.zoomTarget.value) / 1000
    const stageSize = this.stageTarget.clientWidth
    this.adjustingZoom = true
    this.#zoomTo(max > 1 ? Math.exp(Math.log(max) * ratio) : 1, stageSize / 2, stageSize / 2)
    this.adjustingZoom = false
  }

  key(event) {
    if (!this.photo) return
    const step = event.shiftKey ? 50 : 10
    const moves = {
      ArrowLeft: [ step, 0 ],
      ArrowRight: [ -step, 0 ],
      ArrowUp: [ 0, step ],
      ArrowDown: [ 0, -step ]
    }
    if (moves[event.key]) {
      event.preventDefault()
      this.#pan(...moves[event.key])
    } else if (event.key === "+" || event.key === "=") {
      event.preventDefault()
      this.#zoomStep(1.2)
    } else if (event.key === "-" || event.key === "_") {
      event.preventDefault()
      this.#zoomStep(1 / 1.2)
    }
  }

  recenter() {
    if (!this.photo) return
    this.zoomLevel = 1
    this.centre = { x: this.photo.width / 2, y: this.photo.height / 2 }
    this.render()
  }

  #pan(dx, dy) {
    if (!this.photo || (!dx && !dy)) return
    const next = panBy({
      ...this.photo, zoom: this.zoomLevel, centreX: this.centre.x, centreY: this.centre.y,
      dx, dy, stageSize: this.stageTarget.clientWidth
    })
    this.centre = { x: next.centreX, y: next.centreY }
    this.render()
  }

  #zoomStep(factor) {
    const stageSize = this.stageTarget.clientWidth
    this.#zoomTo(this.zoomLevel * factor, stageSize / 2, stageSize / 2)
  }

  #zoomTo(nextZoom, anchorX, anchorY) {
    if (!this.photo) return
    const next = zoomAround({
      ...this.photo, zoom: this.zoomLevel, centreX: this.centre.x, centreY: this.centre.y,
      nextZoom, anchorX, anchorY, stageSize: this.stageTarget.clientWidth
    })
    this.zoomLevel = next.zoom
    this.centre = { x: next.centreX, y: next.centreY }
    this.render()
  }

  #pinch() {
    const [ first, second ] = Array.from(this.pointers.values())
    const rect = this.stageTarget.getBoundingClientRect()
    return {
      distance: Math.hypot(first.x - second.x, first.y - second.y),
      x: (first.x + second.x) / 2 - rect.left,
      y: (first.y + second.y) / 2 - rect.top,
      clientX: (first.x + second.x) / 2,
      clientY: (first.y + second.y) / 2
    }
  }

  #pinchMove() {
    const next = this.#pinch()
    if (this.pinch.distance > 0) {
      this.#zoomTo(this.zoomLevel * (next.distance / this.pinch.distance), next.x, next.y)
    }
    this.#pan(next.clientX - this.pinch.clientX, next.clientY - this.pinch.clientY)
    this.pinch = next
  }

  #previewElement() {
    const preview = document.createElement("span")
    preview.className = this.avatarClassValue
    preview.setAttribute("aria-hidden", "true")
    return preview
  }

  // The live circle beside the name shows exactly the square the form sends.
  #renderPreview(view) {
    const preview = this.previewTarget.firstElementChild
    if (!preview) return
    const size = preview.offsetWidth || 80
    const scale = size / view.rect.side
    preview.style.backgroundImage = `url("${this.objectUrl}")`
    preview.style.backgroundSize = `${this.photo.width * scale}px ${this.photo.height * scale}px`
    preview.style.backgroundPosition = `${-view.rect.left * scale}px ${-view.rect.top * scale}px`
  }

  #renderZoom() {
    const max = maxZoom(this.photo)
    const ratio = max > 1 ? Math.log(this.zoomLevel) / Math.log(max) : 0
    if (!this.adjustingZoom) this.zoomTarget.value = String(Math.round(ratio * 1000))
    this.zoomTarget.setAttribute("aria-valuetext", `${Math.round(this.zoomLevel * 100)} %`)
  }

  #write(rect) {
    const square = placement(rect)
    this.cropXTarget.value = square.x
    this.cropYTarget.value = square.y
    this.cropSizeTarget.value = square.size
    this.cropWidthTarget.value = Math.round(this.photo.width)
    this.cropHeightTarget.value = Math.round(this.photo.height)
  }

  clearCrop() {
    this.probe = null
    this.photo = null
    for (const pointerId of this.pointers.keys()) {
      if (this.stageTarget.hasPointerCapture?.(pointerId)) this.stageTarget.releasePointerCapture(pointerId)
    }
    this.pointers.clear()
    this.lastPoint = null
    this.pinch = null
    this.stageTarget.classList.remove("is-dragging")
    this.cropTarget.hidden = true
    this.cropImageTarget.removeAttribute("src")
    this.cropImageTarget.removeAttribute("style")
    this.previewTarget.innerHTML = this.originalPreview
    this.cropXTarget.value = ""
    this.cropYTarget.value = ""
    this.cropSizeTarget.value = ""
    this.cropWidthTarget.value = ""
    this.cropHeightTarget.value = ""
    this.release()
  }

  release() {
    if (!this.objectUrl) return

    URL.revokeObjectURL(this.objectUrl)
    this.objectUrl = null
  }
}
