import { Controller } from "@hotwired/stimulus";

// The bulk operation's progress page (DESIGN.md §20.4,
// docs/dev/BULK-ACTIONS.md).
//
// The batch-import variant (`batch_import_controller.js`) for the durable bulk
// ledger: poll the status fragment while the operation is active, announce
// meaningful transitions only, and fire one toast when it reaches a terminal
// state. The notice node carries the localized copy so the controller never
// holds user-facing text.
export default class extends Controller {
  static targets = ["content", "announcer"];
  static values = { statusUrl: String };

  connect() {
    this.lastStatus = this.statusText();
    this.schedulePoll();
  }

  disconnect() {
    clearTimeout(this.timer);
    this.abortController?.abort();
  }

  schedulePoll() {
    if (!this.isActive()) return;

    this.timer = setTimeout(() => this.poll(), 2000);
  }

  async poll() {
    this.abortController = new AbortController();

    try {
      const response = await fetch(this.statusUrlValue, {
        headers: { Accept: "text/html" },
        credentials: "same-origin",
        signal: this.abortController.signal
      });
      if (!response.ok) {
        this.schedulePoll();
        return;
      }

      const wasActive = this.isActive();
      this.contentTarget.outerHTML = await response.text();
      this.announce();
      this.notifyOutcome(wasActive);
      this.schedulePoll();
    } catch (error) {
      if (error.name !== "AbortError") this.schedulePoll();
    }
  }

  notifyOutcome(wasActive) {
    if (!wasActive || this.isActive()) return;

    const notice = this.contentTarget?.querySelector("[data-bulk-operation-notice]");
    if (!notice) return;

    window.dispatchEvent(
      new CustomEvent("allure:notify", {
        detail: {
          title: notice.dataset.noticeTitle,
          body: notice.dataset.noticeBody,
          level: notice.dataset.noticeLevel
        }
      })
    );
  }

  // Announce meaningful transitions only — never every 2-second poll. The
  // announcer lives outside the replaced content so it survives each poll.
  announce() {
    const current = this.statusText();
    if (current !== this.lastStatus) {
      this.lastStatus = current;
      if (this.hasAnnouncerTarget) this.announcerTarget.textContent = current;
    }
  }

  statusText() {
    const root = this.hasContentTarget ? this.contentTarget : this.element;
    return [...root.querySelectorAll("[data-status-text]")].map((node) => node.textContent.trim()).join(" — ");
  }

  isActive() {
    return this.contentTarget?.dataset.bulkOperationActive === "true";
  }
}
