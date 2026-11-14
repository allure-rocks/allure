import { Controller } from "@hotwired/stimulus";

// Destructive confirmation (DESIGN.md §10.10).
//
// Replaces the browser-native `data-turbo-confirm` dialog, which cannot state
// consequences, cannot be translated, and cannot be styled. Destructive forms
// carry data-confirm-title / data-confirm-body / data-confirm-verb (on the
// form or the button); a click anywhere inside such a form opens the shared
// modal instead of submitting. The confirm button repeats the verb, cancel is
// focused on open, and Escape/backdrop cancel via Bootstrap's own behaviour.
export default class extends Controller {
  static targets = ["title", "body", "submit", "cancel"];

  connect() {
    this.allowOnce = null;
    this.trigger = null;
    this.modal = new window.bootstrap.Modal(this.element);
    this.onShown = () => this.cancelTarget.focus();
    this.onHidden = () => {
      const form = this.confirmedForm;
      this.confirmedForm = null;
      this.pendingForm = null;
      if (!form?.isConnected) {
        this.trigger?.focus?.();
        return;
      }
      // Let Bootstrap finish its transition before Turbo can replace the page
      // and dispose the modal. Submitting during hide() races _resetAdjustments.
      this.allowOnce = form;
      form.requestSubmit();
    };
    this.element.addEventListener("shown.bs.modal", this.onShown);
    this.element.addEventListener("hidden.bs.modal", this.onHidden);
  }

  disconnect() {
    this.element.removeEventListener("shown.bs.modal", this.onShown);
    this.element.removeEventListener("hidden.bs.modal", this.onHidden);
    this.modal?.dispose();
    this.modal = null;
    this.allowOnce = null;
    this.trigger = null;
    this.pendingForm = null;
    this.confirmedForm = null;
  }

  maybeAsk(event) {
    const scope = event.target instanceof Element ? event.target.closest("[data-confirm-title]") : null;
    if (!scope) return;
    const form = scope instanceof HTMLFormElement ? scope : scope.closest("form");
    if (!form) return;
    if (this.allowOnce === form) {
      this.allowOnce = null;
      return;
    }
    event.preventDefault();
    this.trigger = event.target instanceof HTMLElement ? event.target : null;
    this.pendingForm = form;
    this.titleTarget.textContent = scope.dataset.confirmTitle ?? "";
    this.bodyTarget.textContent = scope.dataset.confirmBody ?? "";
    this.submitTarget.textContent = scope.dataset.confirmVerb ?? "";
    this.modal.show();
  }

  confirm() {
    if (!this.pendingForm) return;
    this.confirmedForm = this.pendingForm;
    this.pendingForm = null;
    this.modal.hide();
  }
}
