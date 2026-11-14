import { Controller } from "@hotwired/stimulus";

// The Public switch applies on change. The hidden input carries the explicit
// "off" value; disabling it while the checkbox is checked keeps the URL free
// of a duplicated `public` parameter. Without JavaScript the Apply button
// submits the same form.
export default class extends Controller {
  static targets = ["form", "hidden", "checkbox"];

  submit() {
    this.hiddenTarget.disabled = this.checkboxTarget.checked;
    this.formTarget.requestSubmit();
  }
}
