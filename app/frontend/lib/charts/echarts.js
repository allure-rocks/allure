// The single entry to Apache ECharts (docs/dev/CHARTS.md). The library is loaded
// on demand, the first time a chart connects, so pages without a chart never
// pay for it; every controller shares the one promise. Only the modules the
// charts use are registered (echarts_modules.js), and only the SVG renderer:
// crisp at every pixel ratio, inspectable, and fast enough for a 1,000-point
// profile.
let loading = null;

export function loadECharts() {
  loading ||= import("./echarts_modules").then((module) => module.default).catch((error) => {
    // A failed chunk download must not poison every later attempt.
    loading = null;
    throw error;
  });
  return loading;
}
