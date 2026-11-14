import { Controller } from "@hotwired/stimulus";

// One server-rendered route image in the reader's theme (DESIGN.md §15.4).
// The server paints the variant matching `data-bs-theme`, so the first frame
// is right and the other URL is one attribute away. `connect` resynchronizes
// a page restored from the Turbo cache, whose stored `src` may predate a
// theme toggle; `themeChanged` follows the toggle — and the companion's own
// appearance — on the shared `allure:theme-changed` event, like the maps and
// the charts. The swap holds no external instance: both URLs live on the
// element, and there is nothing to release on disconnect.
export default class extends Controller {
  static values = {
    lightUrl: String,
    darkUrl: String,
  };

  connect() {
    this.sync(document.documentElement.dataset.bsTheme);
  }

  themeChanged(event) {
    this.sync(event.detail?.theme);
  }

  sync(theme) {
    const url = theme === "dark" ? this.darkUrlValue : this.lightUrlValue;
    if (url && this.element.getAttribute("src") !== url) this.element.src = url;
  }
}
