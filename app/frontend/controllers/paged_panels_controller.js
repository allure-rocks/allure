import { Controller } from "@hotwired/stimulus"

// Paged panels (DESIGN.md §10.25): a selector over whole pages, one page
// visible at a time. Shared by the profile statistics (one measure per page),
// the profile records (one sport per page) and the owner's records page (one
// sport per page). Native scroll snapping supplies the touch gesture; Tabler
// radios supply direct selection and arrow-key navigation. No gesture is
// required.
//
// `fit` sizes the viewport to the selected page, so a short page leaves no
// blank space under its rows (the owner's records page). Without it every page
// keeps the tallest one's height, so changing pages never moves what follows
// (the profile's rail).
export default class extends Controller {
  static targets = ["navigation", "selector", "choice", "viewport", "panel", "status"]
  static values = { fit: { type: Boolean, default: false } }

  connect() {
    if (this.panelTargets.length < 2) return

    this.interactive = true
    this.element.classList.add("paged-panels--interactive")
    if (this.fitValue) this.element.classList.add("paged-panels--fit")
    this.navigationTarget.hidden = false
    this.#activate(Math.max(0, this.choiceTargets.findIndex((choice) => choice.checked)), false)
    this.#align()
    this.resizeObserver = new ResizeObserver(() => {
      this.#align()
      this.#fit()
    })
    this.resizeObserver.observe(this.viewportTarget)
    this.panelTargets.forEach((panel) => this.resizeObserver.observe(panel))
    this.#fit()
  }

  disconnect() {
    this.interactive = false
    clearTimeout(this.scrollTimer)
    this.resizeObserver?.disconnect()
    this.resizeObserver = null
    this.element.classList.remove("paged-panels--interactive", "paged-panels--fit")
    this.viewportTarget.style.removeProperty("height")
    if (this.hasNavigationTarget) this.navigationTarget.hidden = true
    for (const panel of this.panelTargets) {
      panel.inert = false
      panel.removeAttribute("aria-hidden")
      panel.removeAttribute("tabindex")
    }
    this.statusTarget.textContent = ""
  }

  select(event) {
    this.#activate(this.choiceTargets.indexOf(event.currentTarget))
    this.#align()
  }

  scrolled() {
    if (!this.interactive) return

    this.dispatch("scroll")
    clearTimeout(this.scrollTimer)
    this.scrollTimer = setTimeout(() => {
      const viewport = this.viewportTarget
      if (!viewport.clientWidth) return

      const index = Math.round(viewport.scrollLeft / viewport.clientWidth)
      this.#activate(Math.max(0, Math.min(index, this.panelTargets.length - 1)))
    }, 120)
  }

  #activate(index, announce = true) {
    if (index < 0 || index >= this.panelTargets.length) return

    const changed = this.index !== index
    this.index = index
    this.choiceTargets.forEach((choice, position) => { choice.checked = position === index })
    this.panelTargets.forEach((panel, position) => {
      const selected = position === index
      panel.inert = !selected
      panel.setAttribute("aria-hidden", String(!selected))
      panel.tabIndex = selected ? 0 : -1
    })
    if (announce && changed) this.statusTarget.textContent = this.choiceTargets[index].dataset.choiceName
    if (changed) this.dispatch("change", { detail: { index } })
    this.#revealChoice()
    this.#fit()
  }

  #align() {
    if (!this.interactive) return

    clearTimeout(this.scrollTimer)
    this.viewportTarget.scrollTo({ left: this.index * this.viewportTarget.clientWidth, behavior: "instant" })
  }

  // The viewport takes the selected page's own height. Pages keep their
  // natural height (the stylesheet aligns them at the start), so the
  // measurement never reads the height it is about to set. A classic
  // horizontal scrollbar takes layout space out of the content box; overlay
  // scrollbars take none.
  #fit() {
    if (!this.interactive || !this.fitValue) return

    const panel = this.panelTargets[this.index]
    if (!panel) return

    const viewport = this.viewportTarget
    const scrollbar = Math.max(0, viewport.offsetHeight - viewport.clientHeight)
    viewport.style.height = `${Math.ceil(panel.getBoundingClientRect().height) + scrollbar}px`
    // The clipped taller pages must never leave the viewport scrolled down.
    viewport.scrollTop = 0
  }

  #revealChoice() {
    const choice = this.choiceTargets[this.index]
    const item = choice.closest(".form-selectgroup-item") || choice.labels[0]
    const selector = this.selectorTarget
    const left = item.getBoundingClientRect().left - selector.getBoundingClientRect().left + selector.scrollLeft
    if (left < selector.scrollLeft || left + item.offsetWidth > selector.scrollLeft + selector.clientWidth) {
      selector.scrollTo({ left: Math.max(0, left - 4), behavior: "instant" })
    }
  }
}
