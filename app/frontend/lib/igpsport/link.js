import { bytesFromHex, concatBytes, toHex } from "./bytes.js";
import {
  ACTIVITY_CHANNEL,
  COUNT_TIMEOUT_MS,
  DOWNLOAD_IDLE_TIMEOUT_MS,
  HEADER_SIZE,
  INIT_CHANNEL,
  LIST_TIMEOUT_MS,
  MAX_ACTIVITY_BYTES,
  MAX_METADATA_BYTES,
  MODE_FILE_OPERATION,
  NUS_CHANNELS,
  PACKET_DATA,
  PACKET_REQUEST,
  PACKET_RESULT,
  REQUEST_TIMEOUT_MS,
  SERVICE_CYCLING_DATA,
} from "./constants.js";
import { crc8Maxim, craftData, parseHeader } from "./framing.js";
import { NAME_PREFIXES, resolveModel } from "./models.js";
import {
  activityCountPayload,
  activityFilePayload,
  activityListPayload,
  decodeActivityCount,
  decodeActivityList,
  decodeFileMetadata,
  initRequests,
} from "./protobuf.js";

const DEFAULT_TIMEOUTS = {
  request: REQUEST_TIMEOUT_MS,
  count: COUNT_TIMEOUT_MS,
  list: LIST_TIMEOUT_MS,
  downloadIdle: DOWNLOAD_IDLE_TIMEOUT_MS,
};

export class UnsupportedModelError extends Error {
  constructor(name) {
    super(`Unsupported device ${name || "(unnamed)"}`);
    this.name = "UnsupportedModelError";
    this.deviceName = name || "";
  }
}

export class Bsc500Link {
  constructor({ bluetooth = globalThis.navigator?.bluetooth, onLog, onDisconnect, timeouts = {} } = {}) {
    this.bluetooth = bluetooth;
    this.onLog = onLog;
    this.onDisconnect = onDisconnect;
    this.timeouts = { ...DEFAULT_TIMEOUTS, ...timeouts };
    this.device = null;
    this.model = null;
    this.server = null;
    this.txCharacteristics = new Map();
    this.rxCharacteristics = [];
    this.buffers = new Map();
    this.pending = null;
    this.download = null;
    this.stream = null;
    this.intentionalDisconnect = false;
    this.handleDisconnected = this.handleDisconnected.bind(this);
    this.handleNotification = this.handleNotification.bind(this);
  }

  static supported() {
    return Boolean(globalThis.navigator?.bluetooth) && globalThis.isSecureContext === true;
  }

  async connect() {
    if (!this.bluetooth) throw new Error("Web Bluetooth is unavailable in this browser");

    this.device = await this.bluetooth.requestDevice({
      filters: NAME_PREFIXES.map((namePrefix) => ({ namePrefix })),
      optionalServices: NUS_CHANNELS.map((channel) => channel.service),
    });
    this.model = resolveModel(this.device.name);
    if (!this.model) throw new UnsupportedModelError(this.device.name);

    this.device.addEventListener("gattserverdisconnected", this.handleDisconnected);
    this.log(`selected ${this.model.name}; ${this.model.writeSize}-byte writes${this.model.verified ? "" : ", untested model"}`);

    this.server = await this.device.gatt.connect();
    this.log("GATT connected; resolving UART services");

    // Every channel the device exposes is subscribed before any request.
    for (const channel of NUS_CHANNELS) {
      let service;
      try {
        service = await this.server.getPrimaryService(channel.service);
      } catch (error) {
        if (error?.name !== "NotFoundError") throw error;
        if (channel.required) throw new Error(`UART channel ${channel.number} is missing; not a supported iGPSPORT computer`);
        this.log(`ch${channel.number} UART service absent; skipped`);
        continue;
      }
      const [tx, rx] = await Promise.all([
        service.getCharacteristic(channel.tx),
        service.getCharacteristic(channel.rx),
      ]);
      this.txCharacteristics.set(channel.number, tx);
      rx.addEventListener("characteristicvaluechanged", this.handleNotification);
      await rx.startNotifications();
      this.rxCharacteristics.push(rx);
      this.log(`subscribed ch${channel.number} notifications`);
    }
  }

  // The device expects this handshake before file operations; order matters.
  async initialize() {
    const report = { model: { name: this.model.name, verified: this.model.verified } };
    for (const query of initRequests()) {
      let payload;
      try {
        payload = await this.request(
          INIT_CHANNEL.number,
          query.service,
          query.command,
          bytesFromHex(query.payload),
        );
      } catch (error) {
        if (!query.optional || !this.server?.connected) throw error;
        this.log(`no reply from service ${query.service}; continuing`);
        continue;
      }
      if (query.decode) Object.assign(report, query.decode(payload));
    }
    return report;
  }

  async listActivities() {
    const countPayload = await this.request(
      ACTIVITY_CHANNEL,
      SERVICE_CYCLING_DATA,
      8,
      activityCountPayload(),
      { fileOperation: true, timeoutMs: this.timeouts.count },
    );
    const count = decodeActivityCount(countPayload);
    const fileCount = count.fileCount ?? 0;
    const pageSize = count.pageSize || fileCount || 1;
    const activities = [];
    const seen = new Set();

    for (let start = 0; start < fileCount; start += pageSize) {
      const end = Math.min(start + pageSize - 1, fileCount - 1);
      const payload = await this.request(
        ACTIVITY_CHANNEL,
        SERVICE_CYCLING_DATA,
        1,
        activityListPayload(start, end),
        { fileOperation: true, timeoutMs: this.timeouts.list },
      );
      for (const activity of decodeActivityList(payload)) {
        if (seen.has(activity.timestamp)) continue;
        seen.add(activity.timestamp);
        activities.push(activity);
      }
    }

    activities.sort((left, right) => right.timestamp - left.timestamp);
    return { count, activities };
  }

  async downloadActivity(activity, onProgress) {
    if (this.pending) throw new Error("Another request is already in flight");
    if (this.download) throw new Error("An activity download is already in flight");

    const packet = craftData(
      SERVICE_CYCLING_DATA,
      3,
      activityFilePayload(activity.timestamp),
      true,
    );
    const response = new Promise((resolve, reject) => {
      this.download = { resolve, reject, timer: null, onProgress };
      this.touchDownloadTimeout();
    });

    try {
      await this.writePacket(ACTIVITY_CHANNEL, packet);
    } catch (error) {
      this.rejectDownload(error);
    }

    return response;
  }

  disconnect() {
    this.intentionalDisconnect = true;
    if (this.device?.gatt?.connected) {
      this.device.gatt.disconnect();
    } else {
      this.handleDisconnected();
    }
  }

  async request(channel, service, command, payload, options = {}) {
    const { fileOperation = false, timeoutMs = this.timeouts.request } = options;
    if (this.pending) throw new Error("Another request is already in flight");
    if (this.download) throw new Error("An activity download is already in flight");
    if (!this.server?.connected) throw new Error("Bluetooth device is not connected");

    const packet = craftData(service, command, payload, fileOperation);
    const response = new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        if (this.pending?.service === service) this.pending = null;
        reject(new Error(`No response from service ${service} within ${timeoutMs / 1000}s`));
      }, timeoutMs);
      this.pending = { service, expect: PACKET_DATA, resolve, reject, timer };
    });

    try {
      await this.writePacket(channel, packet);
    } catch (error) {
      this.rejectPending(error);
      return response;
    }

    return response;
  }

  // Acknowledged pieces no larger than the model's write size: an oversized
  // write becomes a long write, which this firmware family mishandles.
  async writePacket(channel, packet) {
    const tx = this.txCharacteristics.get(channel);
    if (!tx) throw new Error(`Channel ${channel} write characteristic is unavailable`);
    if (typeof tx.writeValueWithResponse !== "function") {
      throw new Error("This browser does not support acknowledged Bluetooth writes");
    }

    this.log(`TX ch${channel} ${toHex(packet)}`, "tx");
    const size = this.model.writeSize;
    for (let offset = 0; offset < packet.length; offset += size) {
      await tx.writeValueWithResponse(packet.subarray(offset, offset + size));
    }
  }

  handleNotification(event) {
    const view = event.target.value;
    const fragment = new Uint8Array(view.buffer, view.byteOffset, view.byteLength).slice();
    const channel = NUS_CHANNELS.find((item) => item.rx === event.target.uuid)?.number ?? "?";
    if (channel === ACTIVITY_CHANNEL && this.download) this.touchDownloadTimeout();

    try {
      let buffer;
      if (channel === ACTIVITY_CHANNEL && this.stream) {
        buffer = this.appendDownloadStream(fragment);
        if (buffer === null) return;
      } else {
        const existing = this.buffers.get(channel) ?? new Uint8Array();
        const continuingDownload = channel === ACTIVITY_CHANNEL && this.download && existing.length >= HEADER_SIZE;
        if (!continuingDownload) this.log(`RX ch${channel} ${toHex(fragment)}`, "rx");
        buffer = concatBytes(existing, fragment);
      }

      while (buffer.length >= HEADER_SIZE) {
        const header = parseHeader(buffer);
        if (![PACKET_DATA, PACKET_RESULT, PACKET_REQUEST].includes(header.type)) {
          throw new Error(`Unknown packet type 0x${header.type.toString(16)}`);
        }
        if (header.type === PACKET_DATA && header.mode === MODE_FILE_OPERATION) {
          const remaining = this.startDownloadStream(channel, buffer);
          if (remaining === null) {
            this.buffers.set(channel, buffer);
            return;
          }
          buffer = remaining;
          continue;
        }

        const packetSize = header.type === PACKET_DATA ? HEADER_SIZE + header.size : HEADER_SIZE;
        if (buffer.length < packetSize) {
          this.buffers.set(channel, buffer);
          return;
        }

        const packet = buffer.slice(0, packetSize);
        buffer = buffer.slice(packetSize);
        const payload = packet.slice(HEADER_SIZE);
        if (header.type === PACKET_DATA && crc8Maxim(payload) !== packet[9]) {
          throw new Error(`Payload CRC mismatch for service ${header.service}`);
        }
        this.routePacket(channel, header, payload);
      }
      this.buffers.set(channel, buffer);
    } catch (error) {
      this.buffers.set(channel, new Uint8Array());
      this.rejectPending(error);
      this.rejectDownload(error);
      this.log(`ch${channel} ${error.message}`, "bad");
    }
  }

  // Reads the container prefix, then hands the stream to a buffer sized from
  // the declared file size. Returns null until the prefix is complete, then
  // whatever followed a stream that already ended.
  startDownloadStream(channel, buffer) {
    if (channel !== ACTIVITY_CHANNEL || !this.download) {
      throw new Error(`Unexpected file stream on channel ${channel}`);
    }
    if (buffer.length < HEADER_SIZE + 4) return null;

    const metadataSize = new DataView(
      buffer.buffer,
      buffer.byteOffset + HEADER_SIZE,
      4,
    ).getUint32(0, false);
    if (metadataSize > MAX_METADATA_BYTES) {
      throw new Error(`Implausible metadata size ${metadataSize}`);
    }

    const metadataEnd = HEADER_SIZE + 4 + metadataSize;
    if (buffer.length < metadataEnd) return null;

    const metadata = decodeFileMetadata(buffer.slice(HEADER_SIZE + 4, metadataEnd));
    if (metadata.fileSize > MAX_ACTIVITY_BYTES) {
      throw new Error(`Implausible file size ${metadata.fileSize}`);
    }

    this.stream = {
      metadata,
      metadataEnd,
      container: new Uint8Array(metadataEnd + metadata.fileSize),
      received: 0,
      percent: -1,
    };
    return this.appendDownloadStream(buffer) ?? new Uint8Array();
  }

  // Copies stream bytes in place: at 20 bytes per notification, rebuilding
  // the buffer for every fragment would copy it thousands of times over.
  appendDownloadStream(fragment) {
    const stream = this.stream;
    const take = Math.min(fragment.length, stream.container.length - stream.received);
    stream.container.set(fragment.subarray(0, take), stream.received);
    stream.received += take;
    this.reportProgress(Math.max(0, stream.received - stream.metadataEnd), stream.metadata.fileSize);
    if (stream.received < stream.container.length) return null;

    const content = stream.container.slice(stream.metadataEnd);
    const { resolve, timer } = this.download;
    clearTimeout(timer);
    this.download = null;
    this.stream = null;
    this.log(`download stream complete: ${content.length} bytes`);
    resolve({ metadata: stream.metadata, content });
    return fragment.slice(take);
  }

  reportProgress(received, expected) {
    const percent = expected > 0 ? Math.floor((received * 100) / expected) : 100;
    if (percent === this.stream.percent) return;

    this.stream.percent = percent;
    this.download.onProgress?.(received, expected);
  }

  routePacket(channel, header, payload) {
    if (header.type === PACKET_REQUEST) {
      this.log(`ignored ch${channel} device request service=${header.service} command=${header.command}`);
      return;
    }

    const matches =
      this.pending &&
      this.pending.service === header.service &&
      this.pending.expect === header.type;
    if (!matches) {
      const kind = header.type === PACKET_RESULT ? "result" : "data";
      this.log(`unmatched ch${channel} ${kind} service=${header.service} command=${header.command}`);
      return;
    }

    if (header.type === PACKET_RESULT) {
      this.log(`decoded ch${channel} result service=${header.service} command=${header.command} code=${header.resultCode}`);
      this.resolvePending(header);
    } else {
      this.log(`decoded ch${channel} service=${header.service} command=${header.command} payload=${payload.length}B`);
      this.resolvePending(payload);
    }
  }

  touchDownloadTimeout() {
    if (!this.download) return;

    clearTimeout(this.download.timer);
    this.download.timer = setTimeout(() => {
      this.rejectDownload(new Error(`Activity download received no data for ${this.timeouts.downloadIdle / 1000} seconds`));
    }, this.timeouts.downloadIdle);
  }

  resolvePending(value) {
    if (!this.pending) return;

    const { resolve, timer } = this.pending;
    clearTimeout(timer);
    this.pending = null;
    resolve(value);
  }

  rejectPending(reason) {
    if (!this.pending) return;

    const { reject, timer } = this.pending;
    clearTimeout(timer);
    this.pending = null;
    reject(reason);
  }

  rejectDownload(reason) {
    if (!this.download) return;

    const { reject, timer } = this.download;
    clearTimeout(timer);
    this.download = null;
    this.stream = null;
    this.buffers.set(ACTIVITY_CHANNEL, new Uint8Array());
    reject(reason);
  }

  handleDisconnected() {
    this.rejectPending(new Error("Device disconnected"));
    this.rejectDownload(new Error("Device disconnected"));
    this.stream = null;
    this.buffers.clear();
    this.txCharacteristics.clear();
    this.rxCharacteristics = [];
    this.server = null;
    this.log(this.intentionalDisconnect ? "disconnected" : "device disconnected unexpectedly", this.intentionalDisconnect ? "" : "bad");
    this.intentionalDisconnect = false;
    this.onDisconnect?.();
  }

  log(message, kind = "") {
    this.onLog?.(message, kind);
  }
}
