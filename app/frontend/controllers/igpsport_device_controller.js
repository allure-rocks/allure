import { Controller } from "@hotwired/stimulus";

const MAX_LOG_LINES = 200;

export default class extends Controller {
  static targets = [
    "unsupported", "supported", "connect", "disconnect", "refresh", "status",
    "deviceInfo", "model", "untested", "untestedHint", "serial", "battery",
    "activities", "summary", "toggleAll", "list",
    "progressPanel", "progressbar", "progressBar", "progressText", "import", "log",
  ];
  // `native` is set by Rails when the iOS companion registered its `igpsport`
  // bridge component: the radio is then the phone's, through NativeLink.
  static values = { messages: Object, native: Boolean };

  connect() {
    this.link = null;
    this.fit = null;
    this.activities = [];
    this.selection = new Set();
    this.busy = false;
    this.destroyed = false;
    this.disconnecting = false;
    this.dateFormatter = new Intl.DateTimeFormat(document.documentElement.lang || undefined, {
      dateStyle: "medium",
      timeStyle: "short",
    });

    this.supportedTarget.hidden = !this.supported;
    this.unsupportedTarget.hidden = this.supported;
    this.syncControls();
  }

  disconnect() {
    this.destroyed = true;
    this.link?.disconnect();
    this.link = null;
  }

  async connectDevice() {
    if (this.busy || !this.supported) return;

    this.setBusy(true);
    this.setStatus(this.message("connecting"));
    try {
      const { activityDate, activityFilename, validateFit } = await import("../lib/igpsport/fit.js");
      this.fit = { activityDate, activityFilename, validateFit };
      this.link = await this.createLink();
      await this.link.connect();
      this.renderDeviceInfo(await this.link.initialize());
      this.setStatus(this.message("connected"));
    } catch (error) {
      this.releaseFailedLink();
      if (error?.name === "UnsupportedModelError") {
        this.setStatus(this.format(this.message("unsupported_model"), { name: error.deviceName }));
        this.appendLog(error.message, "bad");
      } else {
        this.fail("connect_failed", error);
      }
    } finally {
      this.setBusy(false);
    }
  }

  async createLink() {
    const callbacks = {
      onLog: (message, kind) => this.appendLog(message, kind),
      onDisconnect: () => this.handleDisconnected(),
    };
    if (!this.nativeValue) {
      const { Bsc500Link } = await import("../lib/igpsport/link.js");
      return new Bsc500Link(callbacks);
    }

    const bridge = this.application.getControllerForElementAndIdentifier(this.element, "bridge--igpsport");
    if (!bridge) throw new Error("The app's Bluetooth bridge is unavailable");
    const { NativeLink } = await import("../lib/igpsport/native_link.js");
    return new NativeLink({ bridge, ...callbacks });
  }

  // A computer that connected but failed its handshake is released without
  // the disconnection callback, which would replace the failure status.
  releaseFailedLink() {
    const link = this.link;
    this.link = null;
    if (!link) return;

    link.onDisconnect = null;
    if (link.server || link.connected) link.disconnect();
  }

  disconnectDevice() {
    this.disconnecting = true;
    this.link?.disconnect();
    this.link = null;
    this.syncControls();
  }

  async refresh() {
    if (this.busy || !this.link) return;

    this.setBusy(true);
    this.setStatus(this.message("listing"));
    try {
      const { activities } = await this.link.listActivities();
      this.activities = activities;
      this.selection.clear();
      this.renderActivities();
      this.setStatus("");
    } catch (error) {
      this.fail("list_failed", error);
    } finally {
      this.setBusy(false);
    }
  }

  toggleAll() {
    const allSelected = this.activities.length > 0 && this.selection.size === this.activities.length;
    this.selection = new Set(allSelected ? [] : this.activities.map((activity) => activity.timestamp));
    this.listTarget.querySelectorAll("input[type=checkbox]").forEach((box) => {
      box.checked = !allSelected;
    });
    this.syncSelection();
  }

  async importSelected() {
    if (this.busy || !this.link || !this.fit) return;

    const chosen = this.activities.filter((activity) => this.selection.has(activity.timestamp));
    if (!chosen.length) {
      this.setStatus(this.message("no_selection"));
      return;
    }

    this.setBusy(true);
    const files = [];
    try {
      for (const [index, activity] of chosen.entries()) {
        this.setProgress(index, chosen.length, 0);
        const { metadata, content } = await this.link.downloadActivity(activity, (received, expected) => {
          this.setProgress(index, chosen.length, expected ? received / expected : 0);
        });
        const validation = this.fit.validateFit(content, metadata);
        if (!validation.ok) throw new Error(validation.errors.join("; "));

        const filename = this.fit.activityFilename(activity.timestamp);
        files.push(new File([ content ], filename, { type: "application/octet-stream" }));
      }

      this.setStatus(this.message("handoff"));
      this.handOff(files);
    } catch (error) {
      this.fail("download_failed", error);
    } finally {
      this.setBusy(false);
    }
  }

  handOff(files) {
    const form = this.element.closest("form");
    const input = form?.querySelector('input[type="file"]');
    if (!form || !input || typeof DataTransfer === "undefined") {
      throw new Error(this.message("handoff_failed"));
    }

    const transfer = new DataTransfer();
    for (const file of files) transfer.items.add(file);
    input.files = transfer.files;
    form.requestSubmit();
  }

  handleDisconnected() {
    if (this.destroyed) return;

    const unexpected = !this.disconnecting;
    this.disconnecting = false;
    this.link = null;
    this.activities = [];
    this.selection.clear();
    this.deviceInfoTarget.hidden = true;
    this.activitiesTarget.hidden = true;
    this.progressPanelTarget.hidden = true;
    this.listTarget.replaceChildren();
    this.setStatus(this.message(unexpected ? "unexpected_disconnect" : "disconnected"));
    this.setBusy(false);
  }

  renderDeviceInfo(report) {
    const untested = Boolean(report.model) && !report.model.verified;
    this.modelTarget.textContent = report.model?.name ?? "—";
    this.untestedTarget.hidden = !untested;
    this.untestedHintTarget.hidden = !untested;
    this.serialTarget.textContent = report.serial ?? "—";
    this.batteryTarget.textContent =
      report.battery === null || report.battery === undefined ? "—" : `${report.battery}%`;
    this.deviceInfoTarget.hidden = false;
  }

  renderActivities() {
    this.listTarget.replaceChildren();
    this.activitiesTarget.hidden = this.activities.length === 0;
    this.summaryTarget.textContent = this.format(this.message("summary"), { count: this.activities.length });

    if (!this.activities.length) {
      const empty = document.createElement("li");
      empty.className = "list-group-item text-secondary";
      empty.textContent = this.message("empty");
      this.listTarget.append(empty);
    } else {
      for (const activity of this.activities) this.listTarget.append(this.activityRow(activity));
    }

    this.syncSelection();
  }

  activityRow(activity) {
    const item = document.createElement("li");
    item.className = "list-group-item d-flex align-items-center gap-3";

    const checkbox = document.createElement("input");
    checkbox.type = "checkbox";
    checkbox.className = "form-check-input mt-0";
    checkbox.checked = this.selection.has(activity.timestamp);
    checkbox.setAttribute("aria-label", this.dateFormatter.format(this.fit.activityDate(activity.timestamp)));
    checkbox.addEventListener("change", () => {
      if (checkbox.checked) this.selection.add(activity.timestamp);
      else this.selection.delete(activity.timestamp);
      this.syncSelection();
    });

    const label = document.createElement("div");
    label.className = "flex-fill";
    const date = document.createElement("div");
    date.textContent = this.dateFormatter.format(this.fit.activityDate(activity.timestamp));
    const size = document.createElement("div");
    size.className = "text-secondary small";
    size.textContent = this.formatSize(activity.fileSize);
    label.append(date, size);

    item.append(checkbox, label);
    return item;
  }

  setProgress(index, total, fraction) {
    const percent = Math.max(0, Math.min(100, Math.floor(fraction * 100)));
    this.progressPanelTarget.hidden = false;
    this.progressBarTarget.style.width = `${percent}%`;
    this.progressbarTarget.setAttribute("aria-valuenow", String(percent));
    this.progressTextTarget.textContent = this.format(this.message("downloading"), {
      current: index + 1,
      total,
      percent,
    });
  }

  syncSelection() {
    const allSelected = this.activities.length > 0 && this.selection.size === this.activities.length;
    this.toggleAllTarget.textContent = this.message(allSelected ? "clear_all" : "select_all");
    this.syncControls();
  }

  syncControls() {
    const connected = Boolean(this.link);
    this.connectTarget.hidden = connected;
    this.disconnectTarget.hidden = !connected;
    this.refreshTarget.hidden = !connected;
    this.disconnectTarget.disabled = this.busy;
    this.refreshTarget.disabled = this.busy;
    this.toggleAllTarget.disabled = this.busy || this.activities.length === 0;
    this.importTarget.disabled = this.busy || !connected || this.selection.size === 0;
  }

  setBusy(busy) {
    this.busy = busy;
    this.syncControls();
  }

  setStatus(text) {
    this.statusTarget.textContent = text;
  }

  fail(key, error) {
    const message = error?.message ?? String(error);
    this.setStatus(this.format(this.message(key), { error: message }));
    this.appendLog(message, "bad");
  }

  formatSize(bytes) {
    if (bytes === null || bytes === undefined) return this.message("unknown_size");
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KiB`;

    return `${(bytes / (1024 * 1024)).toFixed(1)} MiB`;
  }

  appendLog(message, kind = "") {
    const line = document.createElement("span");
    line.className = kind;
    line.textContent = `[${new Date().toLocaleTimeString([], { hour12: false })}] ${message}\n`;
    this.logTarget.append(line);
    while (this.logTarget.childElementCount > MAX_LOG_LINES) {
      this.logTarget.firstElementChild.remove();
    }
    this.logTarget.scrollTop = this.logTarget.scrollHeight;
  }

  message(key) {
    return this.messagesValue[key] ?? key;
  }

  format(template, values) {
    return Object.entries(values).reduce(
      (text, [key, value]) => text.replaceAll(`%{${key}}`, String(value)),
      template,
    );
  }

  get supported() {
    return this.nativeValue || (Boolean(navigator.bluetooth) && window.isSecureContext === true);
  }
}
