import { Controller } from "@hotwired/stimulus";

// Light/dark switching.
//
// Tabler's shipped demo script stores the choice in localStorage only. For a
// logged-in user that is the wrong place: the preference belongs to the account
// so it follows them across devices, and it is applied server-side on first
// paint, which avoids a flash of the wrong theme. localStorage stays as the
// fallback for anonymous visitors, who have no account to store anything on.
//
// Icon swapping is left to Tabler's own .hide-theme-light / .hide-theme-dark
// CSS rather than being duplicated here.
export default class extends Controller {
  static values = {
    persistUrl: String,
    current: { type: String, default: "light" },
  };

  toggle(event) {
    event.preventDefault();
    this.currentValue = this.currentValue === "dark" ? "light" : "dark";
    document.documentElement.setAttribute("data-bs-theme", this.currentValue);
    window.dispatchEvent(new CustomEvent("allure:theme-changed", { detail: { theme: this.currentValue } }));
    this.#persist();
  }

  #persist() {
    try {
      window.localStorage.setItem("allure.theme", this.currentValue);
    } catch {
      // Private browsing, or storage disabled. Not worth failing over.
    }

    if (!this.hasPersistUrlValue) return;

    fetch(this.persistUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content ?? "",
      },
      body: JSON.stringify({ theme: this.currentValue }),
    }).catch(() => {
      // The UI has already switched; a failed round-trip only costs persistence.
    });
  }
}
