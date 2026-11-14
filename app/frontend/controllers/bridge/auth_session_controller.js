import { BridgeComponent } from "@hotwired/hotwire-native-bridge";

// A provider sign-in from the iOS companion (PLAN_AUTH.md §9). Providers
// refuse embedded web views, so the app opens the start URL in its system
// browser with a PKCE challenge it keeps, and replies with the handoff token
// and the verifier. They are posted here, from the web view, so the answer is
// resolved in this session: signed in, account creation, a link, or a
// refusal with its flash. A cancelled sheet changes nothing.
export default class extends BridgeComponent {
  static component = "auth-session";
  static values = { startUrl: String, handoffUrl: String };

  start(event) {
    event.preventDefault();
    if (this.pending) return;

    this.pending = true;
    this.element.disabled = true;
    this.send("start", { url: this.startUrlValue }, (message) => {
      this.pending = false;
      this.element.disabled = false;

      const data = message.data ?? {};
      if (data.status === "cancelled") return;
      // A failure posts no token: the server answers with its own flash.
      this.#handOff(data.status === "token" ? data : {});
    });
  }

  #handOff({ token, verifier }) {
    const form = document.createElement("form");
    form.method = "post";
    form.action = this.handoffUrlValue;
    form.hidden = true;
    // Gone before Turbo caches the page it leaves.
    form.dataset.turboTemporary = "";

    const fields = {
      authenticity_token: document.querySelector('meta[name="csrf-token"]')?.content,
      token,
      verifier,
    };
    for (const [name, value] of Object.entries(fields)) {
      if (!value) continue;
      const input = document.createElement("input");
      input.type = "hidden";
      input.name = name;
      input.value = value;
      form.append(input);
    }

    document.body.append(form);
    form.requestSubmit();
  }
}
