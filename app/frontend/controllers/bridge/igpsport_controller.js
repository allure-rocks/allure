import { BridgeComponent } from "@hotwired/hotwire-native-bridge";

// iOS companion radio for the iGPSPORT device source (PLAN_IMPORT_SOURCES.md
// §4.4). Loaded only when the app registers the `igpsport` component; the
// `igpsport-device` controller on the same element drives it through
// `NativeLink`, which sends `connect`, `disconnect`, `list` and `download`
// and reads the replies. The panel, the selection and the batch form stay
// here; the app only lends its Bluetooth.
export default class extends BridgeComponent {
  static component = "igpsport";

  request(event, data, onReply) {
    this.send(event, data, (message) => onReply(message.data));
  }
}
