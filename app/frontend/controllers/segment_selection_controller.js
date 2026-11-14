import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["startIndex", "endIndex", "summary", "error", "submit"];

  static values = {
    hint: String,
    selected: String,
    invalid: String,
  };

  connect() {
    this.connected = true;
    if (this.#hasInputValues()) {
      this.inputChanged();
      // Child map/chart controllers may not have connected when this root
      // controller runs after a validation rerender.
      queueMicrotask(() => {
        if (this.connected && this.#hasInputValues()) this.inputChanged();
      });
    } else {
      this.#clear();
    }
  }

  disconnect() {
    this.connected = false;
  }

  clear() {
    this.#clear();
    window.dispatchEvent(new CustomEvent("allure:segment-selection", { detail: { clear: true } }));
  }

  update(event) {
    const selection = event.detail || {};
    if (selection.clear) {
      if (selection.preserve) {
        this.#showInvalidState(selection.invalid === true);
        return;
      }
      this.#clear(selection.invalid ? this.invalidValue : this.hintValue);
      return;
    }

    const valid = Number.isInteger(selection.startIndex) &&
      Number.isInteger(selection.endIndex) &&
      selection.endIndex > selection.startIndex &&
      selection.startSegmentIndex === selection.endSegmentIndex;
    if (!valid) {
      this.#clear(this.invalidValue);
      return;
    }

    this.startIndexTarget.value = selection.startIndex;
    this.endIndexTarget.value = selection.endIndex;
    this.summaryTarget.textContent = this.selectedValue
      .replace("%{start}", selection.startIndex)
      .replace("%{end}", selection.endIndex);
    this.startIndexTarget.removeAttribute("aria-invalid");
    this.endIndexTarget.removeAttribute("aria-invalid");
    if (this.hasErrorTarget) this.errorTarget.hidden = true;
    if (this.hasSubmitTarget) this.submitTarget.disabled = false;
  }

  inputChanged() {
    const startIndex = this.#integerValue(this.startIndexTarget.value);
    const endIndex = this.#integerValue(this.endIndexTarget.value);
    const hasAnyValue = this.startIndexTarget.value !== "" || this.endIndexTarget.value !== "";

    if (!Number.isInteger(startIndex) || !Number.isInteger(endIndex) || endIndex <= startIndex) {
      this.#showInvalidState(hasAnyValue);
      window.dispatchEvent(new CustomEvent("allure:segment-selection", {
        detail: { clear: true, preserve: true, invalid: hasAnyValue },
      }));
      window.dispatchEvent(new CustomEvent("allure:segment-selection-input", {
        detail: { clear: true, invalid: hasAnyValue },
      }));
      return;
    }

    this.summaryTarget.textContent = this.selectedValue
      .replace("%{start}", startIndex)
      .replace("%{end}", endIndex);
    if (this.hasErrorTarget) this.errorTarget.hidden = true;
    this.startIndexTarget.removeAttribute("aria-invalid");
    this.endIndexTarget.removeAttribute("aria-invalid");
    if (this.hasSubmitTarget) this.submitTarget.disabled = false;
    window.dispatchEvent(new CustomEvent("allure:segment-selection", {
      detail: { startIndex, endIndex },
    }));
    window.dispatchEvent(new CustomEvent("allure:segment-selection-input", {
      detail: { startIndex, endIndex },
    }));
  }

  #clear(message = this.hintValue) {
    if (this.hasStartIndexTarget) this.startIndexTarget.value = "";
    if (this.hasEndIndexTarget) this.endIndexTarget.value = "";
    this.#showInvalidState(message === this.invalidValue);
    if (message !== this.hintValue && this.hasErrorTarget) this.errorTarget.textContent = message;
    if (this.hasSubmitTarget) this.submitTarget.disabled = true;
  }

  #hasInputValues() {
    return this.hasStartIndexTarget && this.hasEndIndexTarget &&
      (this.startIndexTarget.value !== "" || this.endIndexTarget.value !== "");
  }

  #integerValue(value) {
    if (value === "") return null;

    const number = Number(value);
    return Number.isInteger(number) ? number : null;
  }

  #showInvalidState(invalid) {
    if (this.hasSummaryTarget) this.summaryTarget.textContent = this.hintValue;
    if (this.hasErrorTarget) {
      this.errorTarget.hidden = !invalid;
      this.errorTarget.textContent = invalid ? this.invalidValue : "";
    }
    if (this.hasStartIndexTarget) {
      if (invalid) this.startIndexTarget.setAttribute("aria-invalid", "true");
      else this.startIndexTarget.removeAttribute("aria-invalid");
    }
    if (this.hasEndIndexTarget) {
      if (invalid) this.endIndexTarget.setAttribute("aria-invalid", "true");
      else this.endIndexTarget.removeAttribute("aria-invalid");
    }
    if (this.hasSubmitTarget) this.submitTarget.disabled = true;
  }
}
