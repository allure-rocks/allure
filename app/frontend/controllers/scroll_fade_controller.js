import { Controller } from "@hotwired/stimulus";

// A sideways-scrolling line (analysis tabs, route steps): marks which edges
// still hide content with `is-scrollable-start` / `is-scrollable-end`, which
// the CSS turns into faded edges. Recomputed on scroll, on resize, and when
// the line's children change (the route steps are rebuilt per analysis tab).
export default class extends Controller {
  connect() {
    this.update = () => this.#update();
    this.element.addEventListener("scroll", this.update, { passive: true });
    this.resizeObserver = new ResizeObserver(this.update);
    this.resizeObserver.observe(this.element);
    this.mutationObserver = new MutationObserver(() => {
      this.element.scrollLeft = 0;
      this.update();
    });
    this.mutationObserver.observe(this.element, { childList: true, subtree: true });
    this.update();
  }

  disconnect() {
    this.element.removeEventListener("scroll", this.update);
    this.resizeObserver?.disconnect();
    this.mutationObserver?.disconnect();
    this.resizeObserver = null;
    this.mutationObserver = null;
  }

  #update() {
    const element = this.element;
    const maxScroll = element.scrollWidth - element.clientWidth;
    element.classList.toggle("is-scrollable-start", element.scrollLeft > 1);
    element.classList.toggle("is-scrollable-end", maxScroll - element.scrollLeft > 1);
  }
}
