import { Controller } from "@hotwired/stimulus";

// One Bootstrap tooltip on the element, disposed on disconnect so a Turbo
// snapshot never keeps a live instance. The element carries its visible
// content, keyboard focus shows the tooltip, and click toggles it on touch.
//
// `media` (a media query) gates the tooltip: an element that prints its own
// label from a wider size up needs none there, and takes its focus stop with
// it, so the tooltip only ever exists where the label does not.
export default class extends Controller {
  static values = { media: String };

  connect() {
    this.mediaQuery = this.mediaValue ? window.matchMedia(this.mediaValue) : null;
    // Only a focus stop this controller put there is its to take away; an
    // icon-only badge carries its own in the markup.
    this.managesTabIndex = !this.element.hasAttribute("tabindex");
    this.onMediaChange = () => this.applyMedia();
    this.mediaQuery?.addEventListener("change", this.onMediaChange);
    this.applyMedia();
  }

  disconnect() {
    this.mediaQuery?.removeEventListener("change", this.onMediaChange);
    this.mediaQuery = null;
    this.hide();
  }

  applyMedia() {
    if (!this.mediaQuery || this.mediaQuery.matches) this.show();
    else this.hide();
  }

  show() {
    if (this.tooltip) return;
    if (this.managesTabIndex) this.element.setAttribute("tabindex", "0");
    this.tooltip = new window.bootstrap.Tooltip(this.element, {
      trigger: "hover focus click",
      delay: { show: 150, hide: 100 },
    });
  }

  hide() {
    this.tooltip?.dispose();
    this.tooltip = null;
    if (this.managesTabIndex) this.element.removeAttribute("tabindex");
  }
}
