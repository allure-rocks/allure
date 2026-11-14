import { Controller } from "@hotwired/stimulus";
import { anomalyInspecting, setAnomalyInspecting } from "../lib/anomaly_inspect";

// The « Montrer toutes les anomalies sur la carte et le profil » switch of the
// data quality tab; the map and the chart follow it.
export default class extends Controller {
  connect() {
    this.element.checked = anomalyInspecting();
  }

  toggle() {
    setAnomalyInspecting(this.element.checked);
  }
}
