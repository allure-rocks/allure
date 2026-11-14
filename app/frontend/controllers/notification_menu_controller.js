import { Controller } from "@hotwired/stimulus";

// Loads the bell's Turbo Frame when the dropdown opens, and refreshes it on
// every later open. Only the frame body is replaced, so Bootstrap's binding to
// the static trigger survives the refresh.
export default class extends Controller {
  refresh() {
    const frame = this.element.querySelector("turbo-frame#notification-menu");
    if (!frame) return;
    if (frame.src) frame.reload();
    else frame.src = frame.dataset.notificationMenuUrl;
  }
}
