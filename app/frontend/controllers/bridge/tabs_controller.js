import { BridgeComponent } from "@hotwired/hotwire-native-bridge";

// The companion's native tabs (DESIGN.md §7.7). Rails renders the phone bottom
// bar hidden, with the destinations it names; the app draws them as native
// tabs and loads each destination in its own history, so this controller only
// carries the payload.
export default class extends BridgeComponent {
  static component = "tabs";
  static values = { payload: Object };

  connect() {
    super.connect();
    this.send("connect", this.payloadValue);
  }
}
