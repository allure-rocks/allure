import { Controller } from "@hotwired/stimulus";

// What's-new dialog (DESIGN.md §10.11).
//
// The footer version reopens it at any time. After a release it also opens
// itself once per account: the seen marker is a User column, so it follows the
// account across devices, unlike localStorage (DESIGN.md §13.1).
//
// The acknowledgement is sent as soon as the dialog is shown, not when it is
// dismissed: a quick Escape must not make it reappear on the next page. The
// window flag covers the same race while the PATCH is in flight and dies with
// the page session — the account column stays the truth.
export default class extends Controller {
  static targets = ["dismiss"];
  static values = {
    autoShow: Boolean,
    version: String,
    acknowledgeUrl: String,
  };

  connect() {
    this.shown = () => {
      this.dismissTarget.focus();
      if (this.autoShowValue) this.#acknowledge();
    };
    this.element.addEventListener("shown.bs.modal", this.shown);
    this.modal = new window.bootstrap.Modal(this.element);

    if (this.autoShowValue && window.allureReleaseNotesSeen !== this.versionValue) {
      this.modal.show();
    }
  }

  disconnect() {
    this.element.removeEventListener("shown.bs.modal", this.shown);
    this.modal?.dispose();
    this.modal = null;
  }

  #acknowledge() {
    if (window.allureReleaseNotesSeen === this.versionValue) return;
    window.allureReleaseNotesSeen = this.versionValue;

    fetch(this.acknowledgeUrlValue, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content ?? "",
      },
    }).catch(() => {
      // A failed round-trip only means the dialog may reappear next visit.
    });
  }
}
