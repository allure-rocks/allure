import { BridgeComponent } from "@hotwired/hotwire-native-bridge";

// « Sur cet iPhone » on /settings/notifications (docs/dev/PUSH.md). The app
// owns the permission, the relay registration and the device keys; the page
// owns the server-side subscription of this session. The switch reads "on"
// only when both agree: the app is registered and its endpoint is the one
// this session holds. Rendered only for an app that registers `push`.
// The relay binds the endpoint to the instance's VAPID key; after the key
// changed, the card registers the device again on its own.
export default class extends BridgeComponent {
  static component = "push";
  static targets = ["receive", "hide", "unavailable", "denied", "failed"];
  static values = { url: String, serverDigest: String, vapidKey: String };

  connect() {
    super.connect();
    this.requests = new AbortController();
    this.#status();
  }

  disconnect() {
    this.requests.abort();
    super.disconnect();
  }

  toggle() {
    const on = this.receiveTarget.checked;
    this.#busy(true);
    this.#show("failed", false);
    if (on) {
      this.#register();
    } else {
      this.send("unregister", {}, async () => {
        await this.#request("DELETE").catch(() => {});
        this.serverDigestValue = "";
        this.#render(false);
      });
    }
  }

  async hide() {
    const value = this.hideTarget.checked;
    this.hideTarget.disabled = true;
    try {
      const state = await this.#request("PATCH", { hide_content: value });
      this.hideTarget.checked = Boolean(state.hide_content);
    } catch {
      this.hideTarget.checked = !value;
    } finally {
      this.hideTarget.disabled = !this.receiveTarget.checked;
    }
  }

  #register() {
    this.send("register", { vapid_key: this.vapidKeyValue }, (message) => this.#registered(message.data ?? {}));
  }

  #status() {
    this.send("status", {}, async (message) => {
      const { status, endpoint, vapid_key: vapidKey } = message.data ?? {};
      if (status === "unavailable") {
        this.#show("unavailable", true);
        this.receiveTarget.closest("label").hidden = true;
        this.hideTarget.closest("label").hidden = true;
        return;
      }

      // Permission is already granted, so registering again asks nothing; the
      // new endpoint replaces this session's row.
      if (status === "on" && vapidKey !== this.vapidKeyValue) {
        this.#busy(true);
        this.#register();
        return;
      }

      const matches = status === "on" && endpoint && (await this.#matches(endpoint));
      // The device no longer pushes to what this session holds (turned off,
      // denied, or registered anew elsewhere): the server row goes.
      if (!matches && this.serverDigestValue) {
        await this.#request("DELETE").catch(() => {});
        this.serverDigestValue = "";
      }
      this.#show("denied", status === "denied");
      this.#render(Boolean(matches));
    });
  }

  async #registered(data) {
    if (data.status === "registered") {
      try {
        const state = await this.#request("POST", {
          endpoint: data.endpoint,
          p256dh: data.p256dh,
          auth: data.auth,
          hide_content: this.hideTarget.checked,
        });
        this.serverDigestValue = state.endpoint_digest ?? "";
        this.#show("denied", false);
        this.#render(true);
        return;
      } catch {
        // The device registered but this server refused it: undo on the app
        // so both sides agree on "off".
        this.send("unregister", {}, () => {});
      }
    }

    this.#show("denied", data.status === "denied");
    this.#show("failed", data.status !== "denied");
    this.#render(false);
  }

  #render(on) {
    this.receiveTarget.checked = on;
    this.receiveTarget.disabled = false;
    this.hideTarget.disabled = !on;
  }

  #busy(busy) {
    this.receiveTarget.disabled = busy;
    this.hideTarget.disabled = true;
  }

  #show(name, visible) {
    const target = this[`${name}Target`];
    if (target) target.hidden = !visible;
  }

  // The page carries the SHA-256 of this session's endpoint, never the
  // endpoint itself. Without Web Crypto (a non-secure development origin),
  // a server subscription is trusted to be this device's.
  async #matches(endpoint) {
    if (!this.serverDigestValue) return false;
    if (!window.crypto?.subtle) return true;

    const bytes = new TextEncoder().encode(endpoint);
    const digest = await window.crypto.subtle.digest("SHA-256", bytes);
    const hex = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
    return hex === this.serverDigestValue;
  }

  async #request(method, body) {
    const response = await fetch(this.urlValue, {
      method,
      signal: this.requests.signal,
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content ?? "",
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (!response.ok) throw new Error(`push subscription ${response.status}`);

    return response.status === 204 ? {} : response.json();
  }
}
