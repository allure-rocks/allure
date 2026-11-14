import { Controller } from "@hotwired/stimulus";

// Unsaved changes (DESIGN.md §14.3).
//
// A settings form holds entries the server has not seen until its submit, so
// leaving the page — a link, a reload, a closed tab, or another form's save
// that would replace it — asks first. The form's own save never asks.
//
// "Changed" compares each named field with the value the server rendered
// (`defaultValue`, `defaultChecked`, `defaultSelected`), so undoing an edit
// makes the form clean again. Hidden and password fields are never read, and
// neither are unnamed controls (a map's search box, a zoom slider): they are
// not part of what the form submits. A form carrying a validation summary is
// unsaved by definition — the server rendered the submitted values back as the
// new defaults — and a form just submitted counts as saved until the page
// changes, so a save's own redirect is never mistaken for leaving.
//
// The check runs when the page is about to be left, never while typing: no
// listener follows the fields, and nothing is pinned to the viewport.
//
// A form opts out with `data-unsaved-changes="off"` when its fields hold a
// transient choice rather than work (the workout list's bulk selection).
const OPT_OUT = "off";
const FORCED = "forced";
const IGNORED_INPUT_TYPES = new Set(["hidden", "password", "submit", "button", "reset", "image"]);
const NON_FIELD_TAGS = new Set(["FIELDSET", "OUTPUT", "OBJECT", "BUTTON"]);

export default class extends Controller {
  static targets = ["modal", "title", "body", "confirm", "cancel"];
  static values = { messages: Object };

  connect() {
    this.submitted = new WeakSet();
    this.pending = null;
    this.confirmed = null;
    this.allowedVisit = false;
    this.allowedForm = null;

    this.onSubmit = (event) => this.#submitting(event);
    this.onBeforeVisit = (event) => this.#beforeVisit(event);
    this.onBeforeCache = () => this.#beforeCache();
    this.onBeforeUnload = (event) => this.#beforeUnload(event);
    this.onInteraction = () => { this.allowedVisit = false; };
    this.onShown = () => this.cancelTarget.focus();
    this.onHidden = () => this.#leftDialog();

    document.addEventListener("submit", this.onSubmit, true);
    document.addEventListener("turbo:before-visit", this.onBeforeVisit);
    document.addEventListener("turbo:before-cache", this.onBeforeCache);
    document.addEventListener("pointerdown", this.onInteraction, true);
    document.addEventListener("keydown", this.onInteraction, true);
    window.addEventListener("beforeunload", this.onBeforeUnload);

    this.modal = new window.bootstrap.Modal(this.modalTarget);
    this.modalTarget.addEventListener("shown.bs.modal", this.onShown);
    this.modalTarget.addEventListener("hidden.bs.modal", this.onHidden);
  }

  disconnect() {
    document.removeEventListener("submit", this.onSubmit, true);
    document.removeEventListener("turbo:before-visit", this.onBeforeVisit);
    document.removeEventListener("turbo:before-cache", this.onBeforeCache);
    document.removeEventListener("pointerdown", this.onInteraction, true);
    document.removeEventListener("keydown", this.onInteraction, true);
    window.removeEventListener("beforeunload", this.onBeforeUnload);

    this.modalTarget.removeEventListener("shown.bs.modal", this.onShown);
    this.modalTarget.removeEventListener("hidden.bs.modal", this.onHidden);
    this.modal?.dispose();
    this.modal = null;
  }

  confirm() {
    this.confirmed = this.pending;
    this.pending = null;
    this.modal.hide();
  }

  // A page-level form replaces the whole page; a Turbo Frame submission only
  // swaps its frame and leaves the rest of the page, and its entries, alone.
  #pageLevel(form) {
    const explicit = form.getAttribute("data-turbo-frame");
    if (explicit) return explicit === "_top";
    return form.closest("turbo-frame") === null;
  }

  #dirtyForms() {
    return Array.from(document.querySelectorAll("form")).filter((form) => this.#dirty(form));
  }

  #dirty(form) {
    if (this.submitted.has(form)) return false;
    if (form.dataset.unsavedChanges === OPT_OUT) return false;
    // A GET form is a filter or a search: navigation, not entry.
    if ((form.getAttribute("method") || "get").toLowerCase() === "get") return false;
    // A validation summary or an invalid field means the server rendered the
    // submitted values back: the form is unsaved by definition.
    if (form.querySelector(`[data-unsaved-changes="${FORCED}"], .is-invalid`)) return true;
    return Array.from(form.elements).some((field) => this.#changed(field));
  }

  #changed(field) {
    // An unnamed control is not submitted: a search box or a zoom slider is a
    // way to fill the form in, not part of it.
    if (!field.name) return false;

    const tag = field.tagName;
    if (NON_FIELD_TAGS.has(tag)) return false;
    if (tag === "SELECT") return this.#selectChanged(field);
    if (tag === "TEXTAREA") return field.value !== field.defaultValue;
    if (tag !== "INPUT") return false;

    const type = (field.type || "").toLowerCase();
    if (IGNORED_INPUT_TYPES.has(type)) return false;
    if (type === "checkbox" || type === "radio") return field.checked !== field.defaultChecked;
    if (type === "file") return field.files.length > 0;
    return field.value !== field.defaultValue;
  }

  #selectChanged(select) {
    const options = Array.from(select.options);
    if (select.multiple) {
      return options.some((option) => option.selected !== option.defaultSelected);
    }
    // A single select with no `selected` attribute shows its first enabled
    // option; that is the value the server would have rendered.
    let expected = options.findIndex((option) => option.defaultSelected);
    if (expected === -1) expected = options.findIndex((option) => !option.disabled);
    return select.selectedIndex !== expected;
  }

  // A submission is the form's own save: it never asks about itself, and it
  // stops counting as unsaved until the page changes, so its redirect is not
  // mistaken for leaving. Another form on the page holding entries is a
  // different matter — saving this one would drop them.
  #submitting(event) {
    const form = event.target;
    if (!(form instanceof HTMLFormElement)) return;

    if (this.allowedForm === form) {
      this.allowedForm = null;
      this.#markSubmitted(form);
      return;
    }

    const others = this.#dirtyForms().filter((dirty) => dirty !== form);
    if (others.length === 0 || !this.#pageLevel(form)) {
      this.#markSubmitted(form);
      return;
    }

    event.preventDefault();
    this.pending = { kind: "submit", form, submitter: event.submitter ?? null };
    this.#ask("other");
  }

  #markSubmitted(form) {
    if (this.#pageLevel(form)) this.submitted.add(form);
  }

  #beforeVisit(event) {
    if (this.allowedVisit) {
      this.allowedVisit = false;
      return;
    }
    if (this.#dirtyForms().length === 0) return;

    event.preventDefault();
    this.pending = { kind: "visit", url: event.detail?.url };
    this.#ask("leave");
  }

  #beforeUnload(event) {
    if (this.#dirtyForms().length === 0) return;
    event.preventDefault();
    event.returnValue = "";
  }

  // Turbo caches the page it leaves with the fields' current values, so a Back
  // visit would show an unsaved choice as though it had been saved. The cached
  // copy is reset to the server's values; a form carrying a validation summary
  // keeps its state, since its errors belong to the values it shows.
  #beforeCache() {
    this.#dirtyForms()
      .filter((form) => !form.querySelector(`[data-unsaved-changes="${FORCED}"], .is-invalid`))
      .forEach((form) => form.reset());
    this.submitted = new WeakSet();
  }

  #ask(context) {
    const messages = this.messagesValue[context];
    this.titleTarget.textContent = messages.title;
    this.bodyTarget.textContent = messages.body;
    this.confirmTarget.textContent = messages.action;
    // Leaving costs the entries; saving keeps them, so only the first is a
    // destructive choice (DESIGN.md §10.10).
    this.confirmTarget.className = context === "leave" ? "btn btn-danger" : "btn btn-primary";
    this.modal.show();
  }

  // Bootstrap's transitions finish after the click: act once the dialog is
  // gone, as the shared confirmation dialog does.
  #leftDialog() {
    const action = this.confirmed;
    this.confirmed = null;
    this.pending = null;
    if (!action) return;

    if (action.kind === "visit") {
      if (!action.url) return;
      this.allowedVisit = true;
      window.Turbo.visit(action.url);
      return;
    }

    const { form, submitter } = action;
    if (!form.isConnected) return;
    this.allowedForm = form;
    // The submission's own navigation follows at once: it must not ask again.
    this.allowedVisit = true;
    if (submitter?.isConnected && submitter.form === form) form.requestSubmit(submitter);
    else form.requestSubmit();
  }
}
