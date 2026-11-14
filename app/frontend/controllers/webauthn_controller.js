import { Controller } from "@hotwired/stimulus";

// Passkeys and security keys (PLAN_AUTH.md §5.2, DESIGN.md §20.15).
//
// Wraps a form. `start` asks the server for options, lets the person's device
// create or sign the credential, writes the browser's JSON answer into the
// hidden field and submits the form; the server verifies it. Uses the
// browser's own JSON helpers, so no WebAuthn library is shipped.
//
// Where the browser cannot do this (no secure context, an older engine), the
// `available` targets stay hidden and the `unavailable` ones are shown.
export default class extends Controller {
  static targets = ["field", "available", "unavailable", "error"];
  static values = { optionsUrl: String, mode: String, cancelledMessage: String, failedMessage: String };

  connect() {
    const supported = this.#supported();
    this.availableTargets.forEach((element) => (element.hidden = !supported));
    this.unavailableTargets.forEach((element) => (element.hidden = supported));
  }

  disconnect() {
    this.abortController?.abort();
    this.abortController = null;
  }

  async start(event) {
    event.preventDefault();
    if (this.busy) return;

    this.busy = true;
    this.#showError("");
    this.abortController?.abort();
    this.abortController = new AbortController();
    const { signal } = this.abortController;

    try {
      const response = await fetch(this.optionsUrlValue, {
        method: "POST",
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content ?? "",
        },
        signal,
      });
      // A redirect to an HTML page (re-authentication, an expired sign-in)
      // belongs to the whole window.
      if (response.redirected || !response.headers.get("Content-Type")?.includes("application/json")) {
        window.Turbo.visit(response.url);
        return;
      }
      if (!response.ok) throw new Error(`options ${response.status}`);

      const json = await response.json();
      const credential =
        this.modeValue === "create"
          ? await navigator.credentials.create({
              publicKey: PublicKeyCredential.parseCreationOptionsFromJSON(json),
              signal,
            })
          : await navigator.credentials.get({
              publicKey: PublicKeyCredential.parseRequestOptionsFromJSON(json),
              signal,
            });
      if (!this.element.isConnected) return;

      this.fieldTarget.value = JSON.stringify(credential.toJSON());
      this.element.requestSubmit();
    } catch (error) {
      if (error.name === "AbortError" && !this.element.isConnected) return;
      this.#showError(error.name === "NotAllowedError" ? this.cancelledMessageValue : this.failedMessageValue);
    } finally {
      this.busy = false;
    }
  }

  #supported() {
    return (
      window.isSecureContext &&
      typeof window.PublicKeyCredential === "function" &&
      typeof PublicKeyCredential.parseCreationOptionsFromJSON === "function" &&
      typeof PublicKeyCredential.parseRequestOptionsFromJSON === "function"
    );
  }

  #showError(message) {
    if (!this.hasErrorTarget) return;
    this.errorTarget.textContent = message;
    this.errorTarget.hidden = message === "";
  }
}
