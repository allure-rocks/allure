import { Controller } from "@hotwired/stimulus";

import { singleImportFiles } from "../lib/import_single_file";

export default class extends Controller {
  static targets = ["tab", "panel", "submit", "localOnly", "batch", "single"];
  static values = { initial: String };

  #activeSource;

  connect() {
    const initial = this.tabTargets.find((tab) => tab.dataset.source === this.initialValue) ?? this.tabTargets[0];
    if (initial) {
      this.select(initial);
    } else {
      this.#activeSource = "file";
      this.#refreshSingle();
    }
  }

  select(event) {
    const tab = event?.currentTarget ?? event;
    const source = tab?.dataset?.source;
    if (!source) return;
    this.#activeSource = source;
    // A remote source and an archive carry their own fields and submit
    // (docs/dev/REMOTE-IMPORTS.md, PLAN_STRAVA_ARCHIVE.md §8): the upload's
    // options do not apply to them. A manual entry has a form of its own
    // outside the upload form (docs/dev/MANUAL-ENTRY.md), which hides entirely.
    const ownFields = tab.dataset.kind === "remote" || tab.dataset.kind === "archive";
    const manual = tab.dataset.kind === "manual";

    this.tabTargets.forEach((item) => {
      const active = item.dataset.source === source;
      item.classList.toggle("active", active);
      item.setAttribute("aria-selected", active ? "true" : "false");
    });
    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.source !== source;
    });
    if (this.hasBatchTarget) this.batchTarget.hidden = manual;
    if (this.hasSubmitTarget) this.submitTarget.hidden = source !== "file";
    this.localOnlyTargets.forEach((element) => {
      element.hidden = ownFields || manual;
    });
    this.#refreshSingle();
  }

  // A file picked or handed over (the share sheet assigns the input's files
  // and dispatches this event) can turn a batch into a single-file import.
  filesChanged() {
    this.#refreshSingle();
  }

  // The title of the options card applies to the single file a plain upload
  // produces; a device handoff submits at once and a ZIP holds several
  // entries, so neither reveals it. Hiding it drops whatever was typed.
  #refreshSingle() {
    const single = this.#activeSource === "file" && singleImportFiles(this.#fileInput()?.files);

    this.singleTargets.forEach((element) => {
      element.hidden = !single;
      if (!single) element.querySelectorAll("input, textarea").forEach((field) => (field.value = ""));
    });
  }

  #fileInput() {
    const panel = this.panelTargets.find((item) => item.dataset.source === "file");
    return panel?.querySelector('input[type="file"]');
  }
}
