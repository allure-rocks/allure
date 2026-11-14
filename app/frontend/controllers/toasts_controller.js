import { Controller } from "@hotwired/stimulus";

// Async-outcome toasts (DESIGN.md §10.8).
//
// Synchronous feedback stays as inline alerts (flash). This region only carries
// asynchronous outcomes: a batch import finishing, a route image becoming
// available, a recompute completing, a publication being delivered.
//
// Producers append a `.toast` node (e.g. via Turbo Streams) or dispatch
// `allure:notify` on window with `{ title, body, level }`. The controller
// enforces at most three stacked toasts, auto-dismisses after 6 seconds,
// pauses on hover/focus, and always offers manual dismissal.
export default class extends Controller {
  static values = { max: { type: Number, default: 3 }, timeout: { type: Number, default: 6000 } };

  connect() {
    this.timers = new Map();
    this.element.querySelectorAll(":scope > .toast").forEach((node) => this.track(node));
    this.observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        mutation.addedNodes.forEach((node) => {
          if (node instanceof HTMLElement && node.classList.contains("toast")) this.track(node);
        });
      }
    });
    this.observer.observe(this.element, { childList: true });
    this.notifyHandler = (event) => this.notify(event.detail ?? {});
    window.addEventListener("allure:notify", this.notifyHandler);
  }

  disconnect() {
    this.observer?.disconnect();
    window.removeEventListener("allure:notify", this.notifyHandler);
    this.timers?.forEach((timer) => clearTimeout(timer));
    this.timers?.clear();
  }

  notify({ title = "", body = "", level = "info" } = {}) {
    const node = document.createElement("div");
    node.className = "toast show";
    node.setAttribute("role", "status");
    const heading = title
      ? `<div class="toast-header"><strong class="me-auto">${this.#escape(title)}</strong>`
      : `<div class="toast-header"><strong class="me-auto">${this.#escape(level)}</strong>`;
    node.innerHTML =
      `${heading}<button type="button" class="btn-close" data-action="toasts#dismiss" aria-label="Dismiss"></button></div>` +
      (body ? `<div class="toast-body">${this.#escape(body)}</div>` : "");
    this.element.append(node);
    // track() runs via the observer, but appends from notify() in the same
    // frame are covered even if the observer lags.
    if (!this.timers.has(node)) this.track(node);
  }

  dismiss(event) {
    const node = event.target?.closest(".toast") ?? event.currentTarget?.closest(".toast");
    this.#remove(node);
  }

  track(node) {
    while (this.element.querySelectorAll(":scope > .toast").length > this.maxValue) {
      this.#remove(this.element.querySelector(":scope > .toast"));
    }
    this.#arm(node);
    node.addEventListener("mouseenter", () => this.#disarm(node), { once: false });
    node.addEventListener("mouseleave", () => this.#arm(node), { once: false });
    node.addEventListener("focusin", () => this.#disarm(node));
    node.addEventListener("focusout", () => this.#arm(node));
  }

  #arm(node) {
    this.#disarm(node, { keep: true });
    this.timers.set(
      node,
      setTimeout(() => this.#remove(node), this.timeoutValue)
    );
  }

  #disarm(node, { keep = false } = {}) {
    const timer = this.timers.get(node);
    if (timer) clearTimeout(timer);
    if (!keep) this.timers.delete(node);
  }

  #remove(node) {
    if (!node || !node.isConnected) return;
    this.#disarm(node);
    node.remove();
  }

  #escape(value) {
    return String(value).replace(/[&<>"']/g, (char) => ({
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#39;",
    })[char]);
  }
}
