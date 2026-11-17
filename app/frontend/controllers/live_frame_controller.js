import { Controller } from "@hotwired/stimulus";

// Live administration frame (docs/dev/ADMIN.md).
//
// Polls a server-rendered fragment and replaces the frame's content on each
// tick — the established mechanism for live data in this application (Action
// Cable is not mounted; see refresh_controller.js for the pending-media
// variant). Polling pauses while the tab is hidden and in-flight requests are
// aborted on Turbo disconnect. A failed tick keeps the last good content.
// A fragment carrying `data-live-frame-done` is final: polling stops, so a
// settled state never replaces a form being filled in.
export default class extends Controller {
  static values = {
    url: String,
    interval: { type: Number, default: 4000 },
  };

  connect() {
    this.done = this.#settled();
    this.abortController = new AbortController();
    this.visibility = () => (document.hidden ? this.#stop() : this.#start());
    document.addEventListener("visibilitychange", this.visibility);
    this.#start();
  }

  disconnect() {
    this.#stop();
    document.removeEventListener("visibilitychange", this.visibility);
    this.abortController.abort();
  }

  #start() {
    if (this.done || this.timer || document.hidden) return;
    this.timer = window.setInterval(() => this.#refresh(), this.intervalValue);
  }

  #settled() {
    return this.element.querySelector("[data-live-frame-done]") !== null;
  }

  #stop() {
    if (this.timer) window.clearInterval(this.timer);
    this.timer = null;
  }

  async #refresh() {
    try {
      const response = await fetch(this.urlValue, {
        headers: { "Turbo-Frame": this.element.id, Accept: "text/html" },
        signal: this.abortController.signal,
      });
      if (!response.ok) return;
      this.element.innerHTML = await response.text();
      if (this.#settled()) {
        this.done = true;
        this.#stop();
      }
    } catch {
      // Network hiccup or abort: keep the current content, retry on next tick.
    }
  }
}
