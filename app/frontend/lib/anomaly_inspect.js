// Whether the owner inspects every flagged reading on the map and the
// profile, or only the ones that change a figure (DESIGN.md §15.5). Off by
// default and remembered on this browser.
export const ANOMALY_INSPECT_KEY = "allure:anomalies-inspect";
export const ANOMALY_INSPECT_EVENT = "allure:anomalies-inspect";

export function anomalyInspecting() {
  try {
    return localStorage.getItem(ANOMALY_INSPECT_KEY) === "1";
  } catch {
    return false;
  }
}

export function setAnomalyInspecting(inspect) {
  try {
    localStorage.setItem(ANOMALY_INSPECT_KEY, inspect ? "1" : "0");
  } catch {
    // Storage can be disabled; the choice still applies to this page.
  }
  window.dispatchEvent(new CustomEvent(ANOMALY_INSPECT_EVENT, { detail: { inspect } }));
}
