import html2canvas from "html2canvas";
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = {
    submitUrl: String,
    email: String,
    buttonLabel: String,
    captureLabel: String,
    modalTitle: String,
    closeLabel: String,
    undoLabel: String,
    clearLabel: String,
    drawHint: String,
    descriptionLabel: String,
    descriptionPlaceholder: String,
    privacyWarning: String,
    emailLabel: String,
    cancelLabel: String,
    sendLabel: String,
    descriptionRequired: String,
    capturingError: String,
    creating: String,
    created: String,
    submissionError: String,
  };

  connect() {
    this.connected = true;
    this.beforeCache = () => this.cleanup();
    document.addEventListener("turbo:before-cache", this.beforeCache);
    this.mountButton();
  }

  disconnect() {
    this.connected = false;
    document.removeEventListener("turbo:before-cache", this.beforeCache);
    this.cleanup();
  }

  mountButton() {
    this.button = document.createElement("button");
    this.button.type = "button";
    this.button.className = "feedback-widget-fab btn btn-primary shadow-lg";
    this.button.innerHTML = '<i class="ti ti-bug"></i><span></span>';
    this.button.querySelector("span").textContent = this.buttonLabelValue;
    // The label is hidden when the tab retracts on phone/tablet, so the name
    // must not depend on the visible text.
    this.button.setAttribute("aria-label", this.buttonLabelValue);
    this.button.setAttribute("data-bs-title", this.buttonLabelValue);
    this.button.setAttribute("data-controller", "tooltip");
    this.button.addEventListener("click", () => this.capture());
    document.body.appendChild(this.button);
    this.watchScroll();
  }

  // The button slides out while the reader scrolls down and returns on the
  // way up, so it never sits on the content being read (DESIGN.md §7.3). With
  // reduced motion it stays put: the retraction is motion.
  watchScroll() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    this.lastScrollY = window.scrollY;
    this.onScroll = () => {
      const y = window.scrollY;
      const delta = y - this.lastScrollY;
      if (Math.abs(delta) < 8) return;

      const retract = delta > 0 && y > 80;
      this.button?.classList.toggle("is-retracted", retract);
      this.lastScrollY = y;
    };
    window.addEventListener("scroll", this.onScroll, { passive: true });
  }

  cleanup() {
    if (this.onScroll) window.removeEventListener("scroll", this.onScroll);
    this.onScroll = null;
    this.requestController?.abort();
    this.requestController = null;
    this.button?.remove();
    this.button = null;
    this.closeModal();
    this.clearToast();
  }

  async capture() {
    if (!this.button) return;

    const previousContent = this.button.innerHTML;
    this.button.disabled = true;
    this.button.innerHTML = '<span class="spinner-border spinner-border-sm" role="status"></span><span></span>';
    this.button.querySelector("span:last-child").textContent = this.captureLabelValue;

    try {
      const scale = Math.min(window.devicePixelRatio || 1, 2);
      const canvas = await html2canvas(document.documentElement, {
        logging: false,
        useCORS: true,
        foreignObjectRendering: true,
        scale,
        windowWidth: document.documentElement.clientWidth,
        windowHeight: document.documentElement.clientHeight,
        x: window.scrollX,
        y: window.scrollY,
        width: window.innerWidth,
        height: window.innerHeight,
        onclone: (clonedDocument) => this.normalizeUnsupportedColors(clonedDocument),
      });

      if (this.connected) this.openModal(canvas);
    } catch (error) {
      if (this.connected) this.showToast(`${this.capturingErrorValue}: ${error.message || "error"}`, "danger");
    } finally {
      if (this.button) {
        this.button.disabled = false;
        this.button.innerHTML = previousContent;
      }
    }
  }

  openModal(baseCanvas) {
    this.suspendActiveModalFocusTraps();
    this.suspendActiveModalPointerEvents();

    this.modalElement = document.createElement("div");
    this.modalElement.className = "feedback-widget-modal feedback-widget-overlay";
    this.modalElement.tabIndex = 0;
    this.modalElement.setAttribute("role", "dialog");
    this.modalElement.setAttribute("aria-modal", "true");
    this.modalElement.setAttribute("aria-labelledby", "feedbackWidgetModalLabel");
    this.modalElement.innerHTML = `
      <div class="feedback-widget-dialog">
        <div class="feedback-widget-content">
          <div class="feedback-widget-header">
            <h2 class="feedback-widget-title" id="feedbackWidgetModalLabel"><i class="ti ti-bug"></i><span></span></h2>
            <button type="button" class="btn-close" data-feedback-action="close"></button>
          </div>
          <div class="feedback-widget-body">
            <div class="feedback-widget-toolbar">
              <button type="button" class="btn btn-sm btn-light" data-feedback-action="undo"><i class="ti ti-arrow-back-up"></i><span></span></button>
              <button type="button" class="btn btn-sm btn-light" data-feedback-action="clear"><i class="ti ti-eraser"></i><span></span></button>
              <span class="feedback-widget-draw-hint"></span>
            </div>
            <div class="feedback-widget-canvas-wrap"></div>
            <p class="feedback-widget-privacy text-warning-emphasis"><i class="ti ti-shield-lock"></i><span></span></p>
            <div class="mt-3">
              <label class="form-label feedback-widget-description-label"></label>
              <textarea class="form-control" rows="4" required></textarea>
            </div>
            <div class="mt-3">
              <label class="form-label feedback-widget-email-label"></label>
              <input class="form-control" type="email" readonly>
            </div>
          </div>
          <div class="feedback-widget-footer">
            <span class="feedback-widget-status text-muted" role="status" aria-live="polite"></span>
            <div class="d-flex gap-2">
              <button type="button" class="btn btn-secondary" data-feedback-action="cancel"><i class="ti ti-x"></i><span></span></button>
              <button type="button" class="btn btn-primary" data-feedback-action="send"><i class="ti ti-brand-gitlab"></i><span></span></button>
            </div>
          </div>
        </div>
      </div>
    `;
    document.body.appendChild(this.modalElement);

    this.modalElement.querySelector(".feedback-widget-title span").textContent = this.modalTitleValue;
    this.modalElement.querySelector("[data-feedback-action=close]").setAttribute("aria-label", this.closeLabelValue);
    this.modalElement.querySelector("[data-feedback-action=undo] span").textContent = this.undoLabelValue;
    this.modalElement.querySelector("[data-feedback-action=clear] span").textContent = this.clearLabelValue;
    this.modalElement.querySelector(".feedback-widget-draw-hint").textContent = this.drawHintValue;
    this.modalElement.querySelector(".feedback-widget-privacy span").textContent = this.privacyWarningValue;
    this.modalElement.querySelector(".feedback-widget-description-label").textContent = this.descriptionLabelValue;
    this.modalElement.querySelector("textarea").placeholder = this.descriptionPlaceholderValue;
    this.modalElement.querySelector(".feedback-widget-email-label").textContent = this.emailLabelValue;
    this.modalElement.querySelector("input[type=email]").value = this.emailValue;
    this.modalElement.querySelector("[data-feedback-action=cancel] span").textContent = this.cancelLabelValue;
    this.modalElement.querySelector("[data-feedback-action=send] span").textContent = this.sendLabelValue;

    const wrap = this.modalElement.querySelector(".feedback-widget-canvas-wrap");
    baseCanvas.className = "feedback-widget-base-canvas";
    wrap.appendChild(baseCanvas);

    const drawCanvas = document.createElement("canvas");
    drawCanvas.className = "feedback-widget-draw-canvas";
    wrap.appendChild(drawCanvas);

    let strokes = [];
    let currentStroke = null;
    let drawing = false;

    const redraw = () => {
      const context = drawCanvas.getContext("2d");
      context.clearRect(0, 0, drawCanvas.width, drawCanvas.height);
      context.strokeStyle = "#ff3b30";
      context.lineWidth = 3;
      context.lineCap = "round";
      context.lineJoin = "round";

      strokes.forEach((points) => {
        if (!points.length) return;
        context.beginPath();
        context.moveTo(points[0].x, points[0].y);
        points.slice(1).forEach((point) => context.lineTo(point.x, point.y));
        if (points.length === 1) context.lineTo(points[0].x + 0.1, points[0].y + 0.1);
        context.stroke();
      });
    };

    const modalElement = this.modalElement;
    this.resizeOverlay = () => {
      if (this.modalElement !== modalElement) return;
      const maxWidth = wrap.clientWidth;
      if (maxWidth > 0) {
        baseCanvas.style.width = `${Math.min(baseCanvas.width, maxWidth)}px`;
        baseCanvas.style.height = "auto";
      }

      const rect = baseCanvas.getBoundingClientRect();
      drawCanvas.width = Math.max(1, Math.round(rect.width));
      drawCanvas.height = Math.max(1, Math.round(rect.height));
      drawCanvas.style.width = `${rect.width}px`;
      drawCanvas.style.height = `${rect.height}px`;
      redraw();
    };

    const position = (event) => {
      const rect = drawCanvas.getBoundingClientRect();
      return { x: event.clientX - rect.left, y: event.clientY - rect.top };
    };

    drawCanvas.addEventListener("pointerdown", (event) => {
      event.preventDefault();
      drawing = true;
      currentStroke = [position(event)];
      strokes.push(currentStroke);
      drawCanvas.setPointerCapture?.(event.pointerId);
      redraw();
    });
    drawCanvas.addEventListener("pointermove", (event) => {
      if (!drawing) return;
      event.preventDefault();
      currentStroke.push(position(event));
      redraw();
    });
    this.pointerUp = () => {
      drawing = false;
      currentStroke = null;
    };
    this.escapeClose = (event) => {
      if (event.key === "Escape") this.closeModal();
    };
    window.addEventListener("pointerup", this.pointerUp);
    window.addEventListener("resize", this.resizeOverlay);
    window.addEventListener("keydown", this.escapeClose);

    const exportPng = () => {
      const output = document.createElement("canvas");
      output.width = baseCanvas.width;
      output.height = baseCanvas.height;
      const context = output.getContext("2d");
      context.drawImage(baseCanvas, 0, 0);
      if (drawCanvas.width) {
        context.drawImage(drawCanvas, 0, 0, drawCanvas.width, drawCanvas.height, 0, 0, output.width, output.height);
      }
      return output.toDataURL("image/png");
    };

    this.modalElement.addEventListener("click", (event) => {
      const action = event.target.closest("[data-feedback-action]")?.dataset.feedbackAction;
      if (!action) return;
      if (action === "close" || action === "cancel") this.closeModal();
      if (action === "undo") {
        strokes.pop();
        redraw();
      }
      if (action === "clear") {
        strokes = [];
        redraw();
      }
      if (action === "send") this.submit(exportPng());
    });

    this.setupFeedbackFocusGuard();
    this.bodyHadModalOpen = document.body.classList.contains("modal-open");
    this.bodyOverflow = document.body.style.overflow;
    document.body.classList.add("modal-open");
    document.body.style.overflow = "hidden";

    requestAnimationFrame(() => {
      if (this.modalElement !== modalElement) return;
      this.resizeOverlay();
      this.resizeTimer = window.setTimeout(this.resizeOverlay, 60);
      this.modalElement?.querySelector("textarea")?.focus();
    });
  }

  normalizeUnsupportedColors(clonedDocument) {
    const properties = [
      "color",
      "backgroundColor",
      "backgroundImage",
      "borderColor",
      "borderTopColor",
      "borderRightColor",
      "borderBottomColor",
      "borderLeftColor",
      "outlineColor",
      "textDecorationColor",
      "columnRuleColor",
      "fill",
      "stroke",
      "boxShadow",
      "textShadow",
    ];
    const view = clonedDocument.defaultView || window;

    clonedDocument.querySelectorAll("*").forEach((element) => {
      const styles = view.getComputedStyle(element);
      properties.forEach((property) => {
        const value = styles[property];
        if (!value?.includes("color(")) return;
        element.style.setProperty(this.cssPropertyName(property), this.replaceSrgbColors(value));
      });
    });
  }

  cssPropertyName(property) {
    return property.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`);
  }

  replaceSrgbColors(value) {
    return value.replace(
      /color\(\s*srgb\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)(?:\s*\/\s*([\d.]+%?))?\s*\)/gi,
      (_match, red, green, blue, alpha) => {
        const channel = (component) => Math.round(Math.min(1, Math.max(0, Number(component))) * 255);
        const opacity = alpha ? (alpha.endsWith("%") ? Number.parseFloat(alpha) / 100 : Number.parseFloat(alpha)) : 1;
        return `rgba(${channel(red)}, ${channel(green)}, ${channel(blue)}, ${Math.min(1, Math.max(0, opacity))})`;
      },
    );
  }

  closeModal() {
    const modalElement = this.modalElement;
    this.modalElement = null;
    this.requestController?.abort();
    this.requestController = null;
    this.teardownFeedbackFocusGuard();
    window.removeEventListener("pointerup", this.pointerUp);
    window.removeEventListener("resize", this.resizeOverlay);
    window.removeEventListener("keydown", this.escapeClose);
    if (this.resizeTimer) window.clearTimeout(this.resizeTimer);
    this.resizeTimer = null;

    if (!modalElement) return;

    modalElement.remove();
    this.restoreSuspendedModalPointerEvents();
    this.restoreSuspendedModalFocusTraps();

    if (document.querySelector(".modal.show")) {
      document.body.classList.add("modal-open");
      return;
    }

    if (!this.bodyHadModalOpen) document.body.classList.remove("modal-open");
    if (this.bodyOverflow) document.body.style.overflow = this.bodyOverflow;
    else document.body.style.removeProperty("overflow");
  }

  suspendActiveModalFocusTraps() {
    this.suspendedModalFocusTraps = Array.from(document.querySelectorAll(".modal.show"))
      .map((element) => window.bootstrap?.Modal?.getInstance(element))
      .filter((modal) => modal && modal._focustrap);

    this.suspendedModalFocusTraps.forEach((modal) => modal._focustrap.deactivate());
  }

  suspendActiveModalPointerEvents() {
    this.suspendedModalPointerEvents = Array.from(document.querySelectorAll(".modal.show"))
      .map((element) => ({ element, pointerEvents: element.style.pointerEvents }));
    this.suspendedModalPointerEvents.forEach(({ element }) => element.style.setProperty("pointer-events", "none"));
  }

  restoreSuspendedModalPointerEvents() {
    this.suspendedModalPointerEvents?.forEach(({ element, pointerEvents }) => {
      if (pointerEvents) element.style.pointerEvents = pointerEvents;
      else element.style.removeProperty("pointer-events");
    });
    this.suspendedModalPointerEvents = [];
  }

  restoreSuspendedModalFocusTraps() {
    this.suspendedModalFocusTraps?.forEach((modal) => {
      if (modal._element?.classList.contains("show")) modal._focustrap?.activate();
    });
    this.suspendedModalFocusTraps = [];
  }

  setupFeedbackFocusGuard() {
    this.teardownFeedbackFocusGuard();
    this.feedbackFocusGuard = (event) => {
      if (this.modalElement?.contains(event.target)) event.stopImmediatePropagation();
    };
    document.addEventListener("focusin", this.feedbackFocusGuard, true);
  }

  teardownFeedbackFocusGuard() {
    if (!this.feedbackFocusGuard) return;
    document.removeEventListener("focusin", this.feedbackFocusGuard, true);
    this.feedbackFocusGuard = null;
  }

  async submit(screenshot) {
    const description = this.modalElement?.querySelector("textarea")?.value.trim();
    const status = this.modalElement?.querySelector(".feedback-widget-status");
    const sendButton = this.modalElement?.querySelector('[data-feedback-action="send"]');
    if (!status || !sendButton) return;

    if (!description) {
      status.textContent = this.descriptionRequiredValue;
      return;
    }

    sendButton.disabled = true;
    status.textContent = this.creatingValue;
    this.requestController = new AbortController();

    try {
      const response = await fetch(this.submitUrlValue, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "",
        },
        body: JSON.stringify({
          description,
          screenshot,
          pagePath: window.location.pathname,
          userAgent: navigator.userAgent,
          viewport: `${window.innerWidth}x${window.innerHeight}`,
        }),
        signal: this.requestController.signal,
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.errors?.join(", ") || `HTTP ${response.status}`);

      const issueUrl = payload.issueUrl;
      this.closeModal();
      this.showToast(this.createdValue, "success", issueUrl);
    } catch (error) {
      if (error.name === "AbortError") return;
      if (this.modalElement) {
        sendButton.disabled = false;
        status.textContent = `${this.submissionErrorValue}: ${error.message || "error"}`;
      }
    } finally {
      this.requestController = null;
    }
  }

  showToast(message, type, issueUrl) {
    this.clearToast();
    const toast = document.createElement("div");
    toast.className = `feedback-widget-toast alert alert-${type === "danger" ? "danger" : "success"}`;
    toast.setAttribute("role", type === "danger" ? "alert" : "status");
    toast.append(document.createTextNode(message));

    if (issueUrl && /^https?:\/\//i.test(issueUrl)) {
      const link = document.createElement("a");
      link.href = issueUrl;
      link.target = "_blank";
      link.rel = "noopener noreferrer";
      link.textContent = issueUrl;
      toast.append(document.createTextNode(" "), link);
    }

    document.body.appendChild(toast);
    this.toastElement = toast;
    this.toastTimer = window.setTimeout(() => this.clearToast(), 8_000);
  }

  clearToast() {
    if (this.toastTimer) window.clearTimeout(this.toastTimer);
    this.toastTimer = null;
    this.toastElement?.remove();
    this.toastElement = null;
  }
}
