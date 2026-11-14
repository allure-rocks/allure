import { Controller } from "@hotwired/stimulus";

// Styleguide demo helpers (development and test only). Dispatches demo
// content into the shared async-outcome toast region.
export default class extends Controller {
  static values = { title: String, body: String };

  toast() {
    window.dispatchEvent(
      new CustomEvent("allure:notify", {
        detail: { title: this.titleValue, body: this.bodyValue, level: "info" },
      })
    );
  }
}
