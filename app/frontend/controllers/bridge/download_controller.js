import { BridgeComponent } from "@hotwired/hotwire-native-bridge";

// A download link the iOS companion handles natively. WebKit cannot download
// a `Content-Disposition: attachment` response on its own, so the app fetches
// the file with the web session's cookies and offers it to the system (save to
// Files, open in another app). The web keeps the same link for browsers.
export default class extends BridgeComponent {
  static component = "download";
  static values = { url: String };

  connect() {
    super.connect();
    this.element.addEventListener("click", this.#download);
  }

  disconnect() {
    this.element.removeEventListener("click", this.#download);
    super.disconnect();
  }

  #download = (event) => {
    // Only the companion intercepts: a browser follows the link normally.
    if (!this.bridge) return;
    event.preventDefault();
    // Resolve the relative path against the page's URL.
    const url = new URL(this.urlValue, window.location.href).href;
    this.send("download", { url });
  };
}
