import { BridgeComponent } from "@hotwired/hotwire-native-bridge";

import { SharedFiles } from "../../lib/shared_files.js";

// Files the user shared into Allure from another app (share sheet, AirDrop or
// the Files app; docs/dev/IMPORT-SOURCES.md). Loaded only when the app
// registers `shared-files`: the page keeps the panel, the fallback sport and
// the submit, and the app only streams the bytes into the existing input.
export default class extends BridgeComponent {
  static component = "shared-files";
  static targets = ["status"];
  static values = { received: String, failed: String };

  connect() {
    super.connect();
    this.transfer = new SharedFiles({ bridge: this });
    this.#receive();
  }

  // The transport's bridge surface, like `NativeLink`'s.
  request(event, data, onReply) {
    this.send(event, data, (message) => onReply(message.data ?? {}));
  }

  async #receive() {
    try {
      const files = await this.transfer.fetch();
      if (files.length === 0) return;

      this.#attach(files);
    } catch {
      this.#status(this.failedValue);
    }
  }

  #attach(files) {
    const input = this.element.querySelector('input[type="file"]');
    if (!input || typeof DataTransfer === "undefined") return;

    const transfer = new DataTransfer();
    for (const file of files) transfer.items.add(file);
    input.files = transfer.files;
    input.dispatchEvent(new Event("change", { bubbles: true }));

    const names = files.map((file) => file.name).join(", ");
    this.#status(this.receivedValue.replace("%{names}", names));
  }

  #status(text) {
    if (!text || !this.hasStatusTarget) return;

    this.statusTarget.textContent = text;
    this.statusTarget.hidden = false;
  }
}
