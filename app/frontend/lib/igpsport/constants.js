// Only the initialization and activity channels are required: the BSC100S
// has no fifth instance, and the import never writes to the others.
export const NUS_CHANNELS = [
  { number: 1, suffix: "9e", required: true },
  { number: 2, suffix: "8e", required: false },
  { number: 3, suffix: "7e", required: true },
  { number: 4, suffix: "6e", required: false },
  { number: 5, suffix: "3e", required: false },
].map((channel) => ({
  ...channel,
  service: `6e400001-b5a3-f393-e0a9-e50e24dcca${channel.suffix}`,
  tx: `6e400002-b5a3-f393-e0a9-e50e24dcca${channel.suffix}`,
  rx: `6e400003-b5a3-f393-e0a9-e50e24dcca${channel.suffix}`,
}));

export const INIT_CHANNEL = NUS_CHANNELS[0];
export const ACTIVITY_CHANNEL = 3;
export const SERVICE_CYCLING_DATA = 6;
export const SERVICE_BLE = 10;
export const SERVICE_FIRMWARE = 4;
export const SERVICE_FACTORY = 11;
export const SERVICE_DEV_VER_INFO = 17;

export const ACTIVITY_LIST_NUM_GET = 8;
export const ACTIVITY_LIST_GET = 1;
export const ACTIVITY_FILE_GET = 3;

export const HEADER_SIZE = 20;
export const PACKET_DATA = 0x01;
export const PACKET_RESULT = 0x02;
export const PACKET_REQUEST = 0x03;
export const MODE_FILE_OPERATION = 0x55;

export const GARMIN_EPOCH_MS = 631065600000;

export const REQUEST_TIMEOUT_MS = 5_000;
export const COUNT_TIMEOUT_MS = 10_000;
export const LIST_TIMEOUT_MS = 30_000;
export const DOWNLOAD_IDLE_TIMEOUT_MS = 20_000;
export const MAX_METADATA_BYTES = 1024 * 1024;
export const MAX_ACTIVITY_BYTES = 64 * 1024 * 1024;
