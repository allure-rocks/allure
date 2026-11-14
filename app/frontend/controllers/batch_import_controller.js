import { Controller } from "@hotwired/stimulus";

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

  // One toast for the transition out of the active phase. The notice node
  // carries the localized copy so the controller never holds user-facing text.
  notifyOutcome(wasActive) {
    if (!wasActive || this.isActive()) return;

    const notice = this.contentTarget?.querySelector("[data-batch-import-notice]");
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
    return this.contentTarget?.dataset.batchImportActive === "true";
  }
}
