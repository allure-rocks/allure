import { Controller } from "@hotwired/stimulus";

// Submits the form it is attached to when a field changes, so a native
// `<select>` acts as a one-tap selector. Without JavaScript the form keeps its
// `<noscript>` submit button, and every choice stays a plain GET URL.
export default class extends Controller {
  submit() {
    this.element.requestSubmit();
  }
}
