import { Controller } from "@hotwired/stimulus";

// Tabler's one-time-code input (DESIGN.md §20.15): one real text field drawn as
// six slots, so password managers and `one-time-code` autofill still see an
// ordinary input. Created here rather than through `data-bs-toggle="otp"`,
// whose page-load initialisation would miss Turbo visits, and disposed on
// disconnect. A complete code submits its form once the form is valid.
export default class extends Controller {
  static values = { autosubmit: { type: Boolean, default: true } };

  connect() {
    this.otp = new window.bootstrap.OtpInput(this.element, { groups: [3, 3], type: "numeric" });
    this.complete = () => {
      const form = this.element.closest("form");
      if (this.autosubmitValue && form?.checkValidity()) form.requestSubmit();
    };
    this.element.addEventListener("complete.bs.otpInput", this.complete);
    if (this.element.querySelector("input")?.autofocus) this.otp.focus();
  }

  disconnect() {
    this.element.removeEventListener("complete.bs.otpInput", this.complete);
    this.otp?.dispose();
    this.otp = null;
  }
}
