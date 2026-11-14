// One chart's life on a Turbo page: created on the SVG renderer, resized
// with its container (ECharts does not follow the window by itself), and
// disposed with its controller. A fixed `height` or `width` given here stays
// fixed across resizes; the other dimension follows the element. `onResize`
// runs after each resize, for what a controller draws from pixel positions.
export function mountChart(echarts, element, { height, width, autoResize = true, onResize = null } = {}) {
  const chart = echarts.init(element, null, { renderer: "svg", height, width });
  let observer = null;
  if (autoResize && typeof ResizeObserver !== "undefined") {
    // Also covers a chart created inside a closed <details> or a hidden tab:
    // it renders at its real size the moment the element gets one.
    let size = null;
    observer = new ResizeObserver(([entry]) => {
      if (chart.isDisposed()) return;
      const { width: newWidth, height: newHeight } = entry.contentRect;
      if (size && size.width === newWidth && size.height === newHeight) return;
      size = { width: newWidth, height: newHeight };
      chart.resize();
      onResize?.(chart);
    });
    observer.observe(element);
  }

  return {
    chart,
    release() {
      observer?.disconnect();
      observer = null;
      if (!chart.isDisposed()) chart.dispose();
    },
  };
}
