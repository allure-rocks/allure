import { Controller } from "@hotwired/stimulus";

// Workout place filter (DESIGN.md §13.3): a combobox over the owner's
// recorded place names, fetched lazily from the suggestions endpoint so the
// list pages never carry the whole place corpus. The field stays a plain text
// input inside the GET form: without JavaScript the typed value still
// submits, and Enter with no active option falls through to the form's own
// submit. Selecting a suggestion applies the filter immediately, like every
// other select in the bar.
export default class extends Controller {
  static targets = ["input", "list"];
  static values = {
    url: String,
    noResults: { type: String, default: "" },
    debounce: { type: Number, default: 300 },
  };

  connect() {
    this.options = [];
    this.activeIndex = -1;
    this.focused = false;
  }

  disconnect() {
    clearTimeout(this.timer);
    this.abortController?.abort();
  }

  focus() {
    this.focused = true;
    if (this.inputTarget.value.trim() === "") this.fetchSuggestions();
  }

  input() {
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.fetchSuggestions(), this.debounceValue);
  }

  keydown(event) {
    switch (event.key) {
      case "ArrowDown":
        event.preventDefault();
        this.move(1);
        break;
      case "ArrowUp":
        event.preventDefault();
        this.move(-1);
        break;
      case "Enter":
        if (this.activeIndex >= 0) {
          event.preventDefault();
          this.select(this.activeIndex);
        }
        break;
      case "Escape":
      case "Tab":
        this.close();
        break;
    }
  }

  blur() {
    this.focused = false;
    this.close();
  }

  async fetchSuggestions() {
    this.abortController?.abort();
    this.abortController = new AbortController();

    const url = new URL(this.urlValue, window.location.origin);
    const query = this.inputTarget.value.trim();
    if (query) url.searchParams.set("q", query);

    try {
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: this.abortController.signal,
      });
      if (!response.ok) return this.close();

      const data = await response.json();
      if (!this.focused) return;

      this.render(Array.isArray(data.places) ? data.places : []);
    } catch (error) {
      if (error.name !== "AbortError") this.close();
    }
  }

  render(names) {
    this.options = names;
    this.activeIndex = -1;
    this.listTarget.replaceChildren();

    if (names.length === 0) {
      const empty = document.createElement("li");
      empty.className = "dropdown-header";
      empty.setAttribute("role", "option");
      empty.setAttribute("aria-disabled", "true");
      empty.textContent = this.noResultsValue;
      this.listTarget.append(empty);
      this.open();
      return;
    }

    names.forEach((name, index) => {
      const option = document.createElement("li");
      option.className = "dropdown-item";
      option.id = `place-suggestion-${index}`;
      option.setAttribute("role", "option");
      option.textContent = name;
      option.addEventListener("mousedown", (event) => {
        event.preventDefault();
        this.select(index);
      });
      this.listTarget.append(option);
    });
    this.open();
  }

  move(delta) {
    if (this.listTarget.hidden) return this.fetchSuggestions();
    if (this.options.length === 0) return;

    const count = this.options.length;
    this.activeIndex = (this.activeIndex + delta + count) % count;
    this.highlight();
  }

  highlight() {
    Array.from(this.listTarget.children).forEach((child, index) => {
      const active = index === this.activeIndex;
      child.classList.toggle("active", active);
      child.setAttribute("aria-selected", active ? "true" : "false");
    });
    if (this.activeIndex >= 0) {
      this.inputTarget.setAttribute("aria-activedescendant", `place-suggestion-${this.activeIndex}`);
    } else {
      this.inputTarget.removeAttribute("aria-activedescendant");
    }
  }

  select(index) {
    const name = this.options[index];
    if (!name) return;

    this.inputTarget.value = name;
    this.close();
    this.element.closest("form")?.requestSubmit();
  }

  open() {
    this.listTarget.hidden = false;
    this.inputTarget.setAttribute("aria-expanded", "true");
  }

  close() {
    this.listTarget.hidden = true;
    this.activeIndex = -1;
    this.inputTarget.setAttribute("aria-expanded", "false");
    this.inputTarget.removeAttribute("aria-activedescendant");
  }
}
