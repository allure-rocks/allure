import { Controller } from "@hotwired/stimulus";

// Refuses, before uploading, files the server would refuse for their size
// (docs/dev/IMPORT-SOURCES.md): past its limit the request is cut off with a
// bare 413, after the whole upload. Only the visible panel's input is checked,
// since every import panel sits in one form. The message is the server's own,
// rendered into the page.
export default class extends Controller {
  static targets = ["input", "message"];
  static values = { max: Number, text: String };

  connect() {
    this.form = this.element.closest("form");
    this.onSubmit = (event) => this.check(event);
    this.form?.addEventListener("submit", this.onSubmit);
  }

  disconnect() {
    this.form?.removeEventListener("submit", this.onSubmit);
  }

  changed() {
    this.render(this.oversized());
  }

  check(event) {
    if (this.element.closest("[hidden]") || !this.oversized()) return;

    event.preventDefault();
    event.stopImmediatePropagation();
    this.render(true);
    this.inputTarget.focus();
  }

  oversized() {
    const files = [...(this.inputTarget.files || [])];
    return files.reduce((total, file) => total + file.size, 0) > this.maxValue;
  }

  render(oversized) {
    this.inputTarget.classList.toggle("is-invalid", oversized);
    this.inputTarget.setAttribute("aria-invalid", oversized ? "true" : "false");
    this.messageTarget.textContent = oversized ? this.textValue : "";
    this.messageTarget.classList.toggle("d-block", oversized);
  }
}
