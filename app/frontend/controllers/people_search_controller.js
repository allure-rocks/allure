import { Controller } from "@hotwired/stimulus";

// People search (PLAN_PEOPLE.md §3, DESIGN.md §20.22): a combobox over the
// name-search endpoint. The field stays a plain text input inside the resolve
// form, so without JavaScript it still submits an exact handle. The endpoint
// answers an HTML fragment because each result carries a follow form; the
// controller only swaps it into the dropdown.
export default class extends Controller {
  static targets = ["input", "menu"];
  static values = {
    url: String,
    minLength: { type: Number, default: 3 },
    debounce: { type: Number, default: 250 },
  };

  connect() {
    this.timer = null;
    this.abortController = null;
    this.onDocumentClick = (event) => {
      if (!this.element.contains(event.target)) this.close();
    };
    document.addEventListener("click", this.onDocumentClick);
  }

  disconnect() {
    clearTimeout(this.timer);
    this.abortController?.abort();
    document.removeEventListener("click", this.onDocumentClick);
  }

  input() {
    clearTimeout(this.timer);
    const query = this.inputTarget.value.trim();
    if (query.length < this.minLengthValue) return this.close();

    this.timer = setTimeout(() => this.fetchResults(query), this.debounceValue);
  }

  focus() {
    if (this.inputTarget.value.trim().length >= this.minLengthValue) this.input();
  }

  keydown(event) {
    if (event.key !== "Escape") return;

    this.close();
    this.inputTarget.blur();
  }

  async fetchResults(query) {
    this.abortController?.abort();
    this.abortController = new AbortController();

    const url = new URL(this.urlValue, window.location.origin);
    url.searchParams.set("q", query);

    try {
      const response = await fetch(url, {
        headers: { Accept: "text/html" },
        signal: this.abortController.signal,
      });
      if (!response.ok) return this.close();

      this.menuTarget.innerHTML = await response.text();
      this.open();
    } catch (error) {
      if (error.name !== "AbortError") this.close();
    }
  }

  open() {
    this.menuTarget.classList.add("show");
    this.inputTarget.setAttribute("aria-expanded", "true");
  }

  close() {
    this.menuTarget.classList.remove("show");
    this.inputTarget.setAttribute("aria-expanded", "false");
  }
}
