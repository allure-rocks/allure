import { Controller } from "@hotwired/stimulus";

// Live username availability on the sign-up form.
//
// Debounced (≥300ms), aborted when superseded or when Turbo disconnects the
// element, and announced through a polite live region (role="status" in the
// markup). Server-side validation on submit remains authoritative.
export default class extends Controller {
  static targets = ["input", "status"];
  static values = {
    url: String,
    available: String,
    taken: String,
  };

  connect() {
    this.timeout = null;
    this.request = null;
  }

  disconnect() {
    clearTimeout(this.timeout);
    this.request?.abort();
  }

  check() {
    clearTimeout(this.timeout);
    this.timeout = setTimeout(() => this.#lookup(), 300);
  }

  async #lookup() {
    const username = this.inputTarget.value.trim();
    if (username === "") {
      this.statusTarget.textContent = "";
      return;
    }

    this.request?.abort();
    this.request = new AbortController();
    const signal = this.request.signal;

    try {
      const url = new URL(this.urlValue, window.location.origin);
      url.searchParams.set("username", username);
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        signal,
      });
      if (!response.ok) return;
      const { available, reason } = await response.json();
      this.statusTarget.textContent = available ? this.availableValue : `${this.takenValue}${reason ? ` — ${reason}` : ""}`;
      this.statusTarget.classList.toggle("text-success", available);
      this.statusTarget.classList.toggle("text-danger", !available);
    } catch (error) {
      if (error.name !== "AbortError") this.statusTarget.textContent = "";
    }
  }
}
