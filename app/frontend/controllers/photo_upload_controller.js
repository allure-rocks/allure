import { Controller } from "@hotwired/stimulus"

// Upload one file at a time: independent progress/errors and bounded server
// memory. Neither the original nor a temporary object URL is used as a preview.
// The obvious refusals (too large, wrong type, no slot left) are answered here
// so a 20 MB file is never sent to be refused, and the gallery frame morphs on
// success instead of being replaced, which keeps a caption being typed.
export default class extends Controller {
  static targets = ["input", "progress"]
  static values = {
    url: String,
    frame: String,
    error: String,
    maxBytes: Number,
    max: Number,
    remaining: Number,
    types: Array,
    tooLarge: String,
    unsupported: String,
    tooMany: String,
  }

  connect() {
    this.queue = []
    this.active = true
    this.remaining = this.remainingValue
  }

  disconnect() {
    this.active = false
    this.queue = []
    this.request?.abort()
  }

  choose() { this.inputTarget.click() }
  pick() { this.enqueue(this.inputTarget.files); this.inputTarget.value = "" }

  // The whole card or manager column accepts a drop, but only a file drag:
  // the manager's rows are dragged too, and must not offer themselves as
  // uploads.
  dragOver(event) {
    if (!this.#hasFiles(event)) return
    event.preventDefault()
    this.element.classList.add("allure-photo-dragover")
  }

  dragLeave(event) {
    if (this.element.contains(event.relatedTarget)) return
    this.element.classList.remove("allure-photo-dragover")
  }

  drop(event) {
    if (!this.#hasFiles(event)) return
    event.preventDefault()
    this.element.classList.remove("allure-photo-dragover")
    this.enqueue(event.dataTransfer.files)
  }

  // The gallery frame names the real count after every render, so a deletion
  // gives its slot back without a page reload.
  frameRendered(event) {
    if (event.target?.id !== this.frameValue) return
    const tiles = event.target.querySelectorAll("[data-photo-tile]").length
    this.remaining = Math.max(0, this.maxValue - tiles)
  }

  #hasFiles(event) {
    return Array.from(event.dataTransfer?.types ?? []).includes("Files")
  }

  enqueue(files) {
    for (const file of Array.from(files)) {
      if (this.remaining <= 0) { this.#reject(file, this.tooManyValue); continue }
      if (file.size > this.maxBytesValue) { this.#reject(file, this.tooLargeValue); continue }
      if (this.typesValue.length && file.type && !this.typesValue.includes(file.type)) { this.#reject(file, this.unsupportedValue); continue }
      this.queue.push(file)
    }
    if (!this.request) this.uploadNext()
  }

  #reject(file, message) {
    const item = document.createElement("li")
    item.className = "text-danger small"
    item.textContent = `${file.name} — ${message}`
    this.progressTarget.append(item)
  }

  uploadNext() {
    if (!this.active || !this.queue.length) return
    const file = this.queue.shift()
    const item = document.createElement("li")
    item.textContent = `${file.name} `
    const progress = document.createElement("progress")
    progress.max = 100
    progress.setAttribute("aria-label", file.name)
    item.append(progress)
    this.progressTarget.append(item)
    const request = this.request = new XMLHttpRequest()
    request.open("POST", this.urlValue)
    request.setRequestHeader("X-CSRF-Token", document.querySelector('meta[name="csrf-token"]')?.content ?? "")
    request.setRequestHeader("Accept", "application/json")
    request.upload.onprogress = (event) => { if (event.lengthComputable) progress.value = event.loaded / event.total * 100 }
    request.onload = () => {
      if (!this.active) return
      if (request.status === 201) {
        // The tile that replaces this row carries the confirmation. The
        // gallery decides when to refresh: it waits for an open viewer or a
        // caption being typed.
        this.remaining = Math.max(0, this.remaining - 1)
        item.remove()
        window.dispatchEvent(new CustomEvent("allure:photo-uploaded"))
      } else {
        let error = this.errorValue
        try { error = JSON.parse(request.responseText).error || error } catch { /* Non-JSON error page. */ }
        item.append(document.createTextNode(` ${error}`))
        item.classList.add("text-danger")
      }
      this.request = null
      this.uploadNext()
    }
    request.onerror = () => {
      if (!this.active) return
      item.append(document.createTextNode(` ${this.errorValue}`))
      this.request = null
      this.uploadNext()
    }
    const data = new FormData()
    data.append("file", file)
    request.send(data)
  }
}
