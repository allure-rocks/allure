import { BridgeComponent } from "@hotwired/hotwire-native-bridge";

// Pixels of the square PNG the app shows on its 32-point account button.
const AVATAR_SIZE = 96;

// iOS companion bar (DESIGN.md §7.7). Loaded only when the app registers the
// `topbar` component. The server-rendered payload describes the hidden web
// topbar; the app draws it natively and replies with the id of the control
// tapped, which is clicked here so links and forms keep their Turbo behaviour.
// The badge poll keeps running in the hidden bar and forwards its count, and
// the account avatar follows as a PNG for the app's account button.
export default class extends BridgeComponent {
  static component = "topbar";
  static targets = ["badge", "avatar"];
  static values = { payload: Object };

  connect() {
    super.connect();
    this.removePendingCallbacks();
    this.pendingMessageCallbacks = [];
    const payload = { ...this.payloadValue, notifications: this.#notifications() };
    this.send("connect", payload, (message) => this.#click(message.data.id));
    this.#sendAvatar();

    this.observer?.disconnect();
    if (!this.hasBadgeTarget) return;
    this.observer = new MutationObserver(() => this.#sendNotifications());
    this.observer.observe(this.badgeTarget, { childList: true, subtree: true, characterData: true });
  }

  disconnect() {
    this.observer?.disconnect();
    this.observer = null;
    super.disconnect();
  }

  #sendNotifications() {
    this.send("notifications", this.#notifications());
  }

  #notifications() {
    const { notifications } = this.payloadValue;
    if (!this.hasBadgeTarget) return notifications;
    const badge = this.badgeTarget.querySelector("[data-label]");
    return {
      id: notifications.id,
      label: badge?.dataset.label ?? notifications.title,
      unread: Boolean(badge),
      // The companion's app icon badge follows it (docs/dev/PUSH.md).
      count: badge ? Number(badge.dataset.count) || 0 : 0,
    };
  }

  #click(id) {
    const control = this.element.querySelector(`[data-bridge-item="${CSS.escape(id)}"]`);
    control?.click();
  }

  // Generated avatars are inline SVG, never an image file (DESIGN.md §9.2),
  // so the page draws whichever avatar it renders. A failure leaves the app's
  // generic account symbol.
  async #sendAvatar() {
    const source = this.hasAvatarTarget ? this.avatarTarget.querySelector("img, svg") : null;
    if (!source) return;
    try {
      const image = await avatarImage(source);
      const canvas = document.createElement("canvas");
      canvas.width = AVATAR_SIZE;
      canvas.height = AVATAR_SIZE;
      canvas.getContext("2d").drawImage(image, 0, 0, AVATAR_SIZE, AVATAR_SIZE);
      if (!this.element.isConnected) return;
      this.send("avatar", { image: canvas.toDataURL("image/png") });
    } catch {
      // Not decodable or not drawable: nothing to send.
    }
  }
}

async function avatarImage(source) {
  if (source instanceof HTMLImageElement) {
    await source.decode();
    return source;
  }
  const svg = source.cloneNode(true);
  svg.setAttribute("width", AVATAR_SIZE);
  svg.setAttribute("height", AVATAR_SIZE);
  const image = new Image();
  image.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(new XMLSerializer().serializeToString(svg))}`;
  await image.decode();
  return image;
}
