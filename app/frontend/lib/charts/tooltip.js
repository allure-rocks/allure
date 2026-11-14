// Every chart tooltip looks like the page's Bootstrap tooltips: the content
// is the controller's own HTML, and the wrapper is painted by
// `.allure-echarts-tooltip` (styles/components/_chart.scss) instead of
// ECharts' white box. `confine` keeps it inside the chart, so a card's
// overflow never cuts it.
export function tooltipBase(overrides = {}) {
  return {
    className: "allure-echarts-tooltip",
    backgroundColor: "transparent",
    borderWidth: 0,
    padding: 0,
    extraCssText: "box-shadow: none;",
    confine: true,
    transitionDuration: 0,
    ...overrides,
  };
}
