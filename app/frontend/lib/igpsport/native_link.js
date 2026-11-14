import { concat, decodeBase64 } from "../bytes.js";
import { resolveModel } from "./models.js";

// The companion's Bluetooth behind the same surface as `Bsc500Link`: the
// panel controller cannot tell them apart. The app finds the computer, runs
// the handshake, lists and downloads; every reply names its `status`.
export { concat, decodeBase64 };
export class NativeLink {
  constructor({ bridge, onLog, onDisconnect }) {
    this.bridge = bridge;
    this.onLog = onLog;
    this.onDisconnect = onDisconnect;
    this.report = null;
    this.connected = false;
    this.closed = false;
  }

  connect() {
    return new Promise((resolve, reject) => {
      this.bridge.request("connect", {}, (reply) => {
        switch (reply.status) {
          case "log":
            this.onLog?.(reply.message, reply.kind);
            break;
          case "connected":
            this.connected = true;
            this.report = {
              model: nativeModel(reply.name),
              serial: reply.serial ?? null,
              battery: reply.battery ?? null,
            };
            this.onLog?.(`connected to ${reply.name || "unnamed device"}`);
            resolve();
            break;
          case "disconnected":
            this.handleDisconnected();
            break;
          case "cancelled":
          case "failed":
            reject(new Error(reply.error || "Connection cancelled"));
            break;
          default:
            break;
        }
      });
    });
  }

  // The app already ran the handshake while connecting.
  async initialize() {
    if (!this.report) throw new Error("Bluetooth device is not connected");
    return this.report;
  }

  listActivities() {
    return new Promise((resolve, reject) => {
      this.bridge.request("list", {}, (reply) => {
        if (reply.status === "listed") {
          resolve({ activities: reply.activities ?? [] });
        } else {
          reject(new Error(reply.error || "Listing failed"));
        }
      });
    });
  }

  // Progress, then the file in base64 chunks, then its metadata.
  downloadActivity(activity, onProgress) {
    return new Promise((resolve, reject) => {
      const parts = [];
      this.bridge.request(
        "download",
        { timestamp: activity.timestamp, fileSize: activity.fileSize ?? null },
        (reply) => {
          switch (reply.status) {
            case "progress":
              onProgress?.(reply.received, reply.expected);
              break;
            case "chunk":
              parts[reply.index] = decodeBase64(reply.data);
              break;
            case "complete": {
              const content = concat(parts);
              onProgress?.(content.length, content.length);
              resolve({
                metadata: {
                  fileSize: reply.fileSize,
                  fileId: reply.fileId ?? null,
                  fileName: reply.fileName ?? null,
                  fileCrc32: reply.fileCrc32 ?? null,
                },
                content,
              });
              break;
            }
            case "failed":
              reject(new Error(reply.error || "Download failed"));
              break;
            default:
              break;
          }
        },
      );
    });
  }

  // The panel resets itself at once, as the browser link does when the GATT
  // server reports the disconnection it asked for.
  disconnect() {
    if (this.closed) return;
    this.bridge.request("disconnect", {});
    this.handleDisconnected();
  }

  handleDisconnected() {
    if (this.closed) return;
    this.closed = true;
    this.connected = false;
    this.report = null;
    this.onDisconnect?.();
  }
}

// The app's chooser already filtered the family; a name this side does not
// know is shown as untested rather than refused.
function nativeModel(name) {
  if (!name) return null;

  const model = resolveModel(name);
  return { name, verified: model?.verified ?? false };
}
