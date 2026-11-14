import { Controller } from "@hotwired/stimulus";

// Copies a read-only field's value (a fresh API token, the API base URL) and
// confirms it in the button's own label for a moment. Without the Clipboard
// API (an insecure origin), the value is selected so the person can copy it.
export default class extends Controller {
  static targets = ["source", "label"];
  static values = { copiedLabel: String };

  disconnect() {
    clearTimeout(this.timer);
  }

  async copy() {
    const value = this.sourceTarget.value ?? this.sourceTarget.textContent;
    try {
      await navigator.clipboard.writeText(value);
      this.confirm();
    } catch {
      this.sourceTarget.select?.();
    }
  }

  confirm() {
    if (!this.hasLabelTarget || !this.copiedLabelValue) return;

    this.original ??= this.labelTarget.textContent;
    this.labelTarget.textContent = this.copiedLabelValue;
    clearTimeout(this.timer);
    this.timer = setTimeout(() => {
      this.labelTarget.textContent = this.original;
    }, 2000);
  }
}
