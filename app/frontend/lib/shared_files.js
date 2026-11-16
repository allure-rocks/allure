import { concat, decodeBase64 } from "./bytes.js";

// The app's side of the `shared-files` bridge (docs/dev/IMPORT-SOURCES.md).
// When the user shares a file into Allure from another app, the app holds it
// and Rails' batch import page asks for it: one `connect` returns a manifest,
// then each `download` streams the file in base64 chunks. This class turns
// that contract into `File`s the form's input can take. The bridge object is
// the `bridge--shared-files` controller, whose `request` sends an event and
// routes every reply to `onReply`, like `NativeLink`'s.
export class SharedFiles {
  constructor({ bridge }) {
    this.bridge = bridge;
  }

  // The files the app is holding, or an empty array when it has none.
  async fetch() {
    const entries = await this.#manifest();
    const files = [];
    for (const entry of entries) files.push(await this.#file(entry));
    return files;
  }

  #manifest() {
    return new Promise((resolve) => {
      this.bridge.request("connect", {}, (reply) => {
        resolve(reply.status === "files" ? (reply.files ?? []) : []);
      });
    });
  }

  #file(entry) {
    return new Promise((resolve, reject) => {
      const parts = [];
      this.bridge.request("download", { index: entry.index }, (reply) => {
        switch (reply.status) {
          case "chunk":
            parts[reply.index] = decodeBase64(reply.data);
            break;
          case "complete":
            resolve(new File([concat(parts)], entry.name, {
              type: entry.type || "application/octet-stream",
            }));
            break;
          case "failed":
            reject(new Error(reply.error || "Transfer failed"));
            break;
          default:
            break;
        }
      });
    });
  }
}
