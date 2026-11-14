import { Controller } from "@hotwired/stimulus";

// Refreshes a Turbo Frame's content while the server keeps rendering a
// pending marker. The controller swaps the response body itself instead of
// setting a frame `src`, so a still-pending response cannot trigger an
// immediate reload loop. It stops when the marker disappears and aborts any
// in-flight request on disconnect.
export default class extends Controller {
  static values = {
    url: String,
    interval: { type: Number, default: 4000 },
  };

  connect() {
    this.abortController = new AbortController();
    this.timer = window.setInterval(() => this.refresh(), this.intervalValue);
  }

  disconnect() {
    window.clearInterval(this.timer);
    this.abortController?.abort();
  }

  async refresh() {
    try {
      const response = await fetch(this.urlValue, {
        headers: { "Turbo-Frame": this.element.id, Accept: "text/html" },
        signal: this.abortController.signal,
      });
      if (!response.ok) return;

      this.element.innerHTML = await response.text();
      if (!this.element.querySelector("[data-media-pending]")) {
        window.clearInterval(this.timer);
      }
    } catch {
      // A failed refresh keeps the current content and the polling cadence.
    }
  }
}
