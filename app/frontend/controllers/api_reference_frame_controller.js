import { Controller } from "@hotwired/stimulus";

// The iframe holding the Scalar API reference (PLAN_API.md §13.2). The
// reference is its own document, so it follows the page's light/dark switch
// through a same-origin message: on load, and on every allure:theme-changed.
export default class extends Controller {
  connect() {
    this.onThemeChanged = () => this.sync();
    window.addEventListener("allure:theme-changed", this.onThemeChanged);
  }

  disconnect() {
    window.removeEventListener("allure:theme-changed", this.onThemeChanged);
  }

  sync() {
    const theme = document.documentElement.dataset.bsTheme === "dark" ? "dark" : "light";
    this.element.contentWindow?.postMessage({ type: "allure:theme", theme }, window.location.origin);
  }
}
