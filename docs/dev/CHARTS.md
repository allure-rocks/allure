# Charts contract

Every chart renders through Apache ECharts on the SVG renderer, loaded on
demand. This document defines the shared foundation, the rules every chart
follows, and the chart-by-chart contracts. It is a frontend contract: no
payload, endpoint, snapshot or federation contract changes.

## 1. Shared foundation (`app/frontend/lib/charts/`)

| File | Contract |
|---|---|
| `echarts.js` | `loadECharts()`: one cached dynamic import of `echarts_modules.js`. A failed download resets the cache. |
| `echarts_modules.js` | `echarts/core` with only the modules in use registered by named import, so the chunk is tree-shaken: line, bar, scatter, pie, radar; grid, radar, tooltip, toolbox, brush, dataZoom, markPoint, markLine, markArea, graphic, legend; `SVGRenderer`. Never imported statically. |
| `lifecycle.js` | `mountChart(echarts, element, { height, width, autoResize, onResize })` returns `{ chart, release }`: `init` on the SVG renderer, a `ResizeObserver` calling `chart.resize()` then `onResize` (ECharts does not follow the window by itself; this also renders a chart created at 0 × 0 inside a closed `<details>`), and `dispose()` on release. A fixed height or width stays fixed across resizes. |
| `theme.js` | `chartColors()` resolves Tabler tokens through `cssColor()` for the active theme (`--primary`, `--secondary`, `--body-color`, `--border-color`, `--bg-surface`, and the series palette primary/green/azure/purple/orange that Tabler's chart layer defined). `chartFont()` names the page's real font stack (ECharts measures labels on a canvas, where `inherit` means nothing, and the layout would reserve room for a narrower face). `withAlpha()` makes gradient and band colours. `dateFormatter` and `timeAxisFormatter` format dates through `Intl.DateTimeFormat` in the page locale; a time-axis tick prints the precision it carries (year, month or day). |
| `tooltip.js` | `tooltipBase()`: `confine: true`, no ECharts box; the wrapper wears `.allure-echarts-tooltip`, the inverted Bootstrap tooltip surface (hidden while ECharts has not filled it yet). |

Rules:

- **SVG renderer only.** Profiles are bounded to 1,000 points and the pulse
  draws about 104 bars per window; SVG is crisp at any pixel ratio and
  inspectable.
- **No ECharts locale.** Every visible string is ours; dates go through `Intl`.
- **No ECharts theme module and no `darkMode`.** Every colour and position is
  explicit, so ECharts 6's default theme changes do not apply. A theme change
  (`allure:theme-changed`) rebuilds or re-colours the chart.
- **Explicit grid geometry.** A chart that draws HTML over its plot sets the
  grid in pixels with `outerBoundsMode: "none"`, so the plot rectangle is the
  container minus those insets and pixel positions come from the public
  `convertToPixel` / `convertFromPixel`. Charts that only need their labels to
  fit use `outerBoundsMode: "same"`.
- **Public API only**: `setOption`, `dispatchAction`, `on`/`off`,
  `convertToPixel`, `convertFromPixel`, `resize`, `dispose`, `getZr()`,
  `format.truncateText` for bounded radar axis names.
- **Animation**: off for the profile, the stats and the pulse; the donut and
  the progression keep a short animation unless `prefers-reduced-motion`.
- **Accessibility**: `aria.enabled` stays false; charts are `aria-hidden` and
  the server-rendered tables remain the text equivalent.

## 2. Chart by chart

### 2.1 Stats (`stats_chart_controller.js`)

- By sport: **horizontal bars** (`DESIGN.md` §15.1), category axis inverted so
  the first sport is on top, about 32 px per sport with a floor, long names
  truncated with the full name in the tooltip.
- By time: a time axis with one smoothed (`smoothMonotone: "x"`) area line per
  sport; calendar-day periods are read in the reader's zone.
- The unit label is translated (`units.symbols.*`); the chart follows a live
  theme change.

### 2.2 Sport mix (`hub_pie_controller.js`)

- `pie` with an inner radius, no slice labels, a slight emphasis scale.
- The centre text is a `graphic` rich-text element.
- The legend is **our HTML** (`hub-mix-legend`: buttons with Stimulus actions
  carrying the share, `aria-pressed` on the selected sport; hover and focus
  highlight the slice through `dispatchAction`), keyboard reachable, styled by
  Tabler; it wraps under the donut on a narrow card.
- Phones (under 576 px) resize the chart to 170 px through `resize({ height })`.

### 2.3 Course progression (`segment_progress_chart_controller.js`)

- Trend lines (`silent`, dotted where uncertain) plus an effort `scatter` with
  item tooltips; the time axis keeps 3 % of air on both sides.
- The trophies are `graphic` images placed with `convertToPixel` once the chart
  has rendered and after every resize; when one would leave the top, the grid
  moves down by what it needs and the placement runs again.

### 2.4 Intensity pulse (`hub_pulse_controller.js`)

- Two stacked mirrored `bar` series with a per-item colour and per-side corner
  radius; one `marks` scatter series carries the rest-week dots, the baseline
  and cursor `markLine`s and the cursor label `markPoint`, so moving the cursor
  updates that series alone. The category axis holds indexes, the labels come
  from the payload, and a label that would cross a window's edge is skipped.
- `grid` with zero side insets keeps consecutive windows meeting without a
  seam.
- The windowing (one instance per ~104-week chunk inside the scroller) is
  unchanged.

### 2.5 Elevation profile (`elevation_chart_controller.js`)

- Elevation `line` with a gradient `areaStyle`, the optional secondary metric
  on a second y axis (inverted for pace). Gaps stay gaps (`connectNulls: false`).
- The grid is set in pixels with `outerBoundsMode: "none"`; under the plot it
  keeps the tick row, the axis title and, with two series, the legend. HTML
  overlays (whole-distance ticks, top axis values, anomaly dashes, touch
  selection band) are placed from that rectangle, `convertToPixel` and
  `convertFromPixel`, after the first render, every resize and every zoom.
- Chart → map hover reads the pointer through `getZr()` mouse events,
  `containPixel("grid")` and `convertFromPixel`; the cursor (dotted rule and
  ball) is two fixed `graphic` elements updated in place once per frame,
  whichever side moves it.
- Places, analysis pictograms, stop panel, lap boundaries and the focus band
  are `markPoint`, `markLine` and `markArea` on the anchor series, rebuilt only
  when the tab, the focus or the places change; they follow a zoom by
  themselves. The reading tooltip names the places and pictograms within 10 px
  of the pointer.
- Zoom: the toolbox's select-zoom on fine pointers (the toolbox must be shown
  for the feature to exist: its buttons are empty and sized to nothing); a
  passive `inside` `dataZoom` with every interaction off receives the touch
  long-press selection and the reset.
- Selection mode (`segments/new`): a `lineX` brush without toolbox buttons; the
  keyboard fields set the band through `dispatchAction({ type: "brush" })`,
  on the nearest plotted point (the profile is bounded to 1,000 points), which
  raises no `brushEnd` and so never echoes back into the fields.
- A theme change rebuilds the chart.

### 2.6 Shared profile totals (`profile_radar_controller.js`)

- Local opt-in only (`DESIGN.md` §19.38/§20.14), never inferred from the
  publication journal. Only count, distance, moving time and ascent are
  embedded.
- One sport per radar axis, the same order and scale for all applicable sports.
  The profile's `paged-panels` native scroll-snap pager switches the measure,
  independently of the record card's sport choice and the journal filters.
- ECharts' radar has no native log axis: transform every numeric value with
  `Math.log1p` on its stored SI value, and use the same transformed maximum for
  every indicator. Zero remains zero, nil is absent, and nothing is normalized
  independently. The visible copy names the logarithmic scale; the untransformed
  maximum and the server-rendered tables keep the real units and figures.
- One or two sports use horizontal bars, not fabricated radar axes. No animation
  or chart pointer capture; native horizontal and vertical touch scrolling stay
  available. Labels may truncate, never the equivalent table's sport names.
- Pointer listeners live on the chart's outer visual wrapper, with the ECharts
  surface remaining pointer-transparent. Hit testing uses our explicit radar
  centre, radius, start angle and common log scale (radar's public pixel
  converters are not implemented); bars use `convertToPixel`. Hover and a short,
  stationary touch show full sport names and the server-formatted raw figures,
  never the logarithms. No prevented default or pointer capture; scroll/cancel,
  panel changes and teardown clear the reading. The shared tooltip surface is
  confined inside the chart, with text inserted through `textContent`.
- On-demand loading, SVG renderer, `mountChart`/`release`, theme updates, and
  guards against a pending import completing after disconnect. A failed chart
  leaves its open data disclosure readable.

## 3. Bundle

The library is a separate chunk, loaded by the first chart that connects. A
page without a chart downloads no chart library at all.

## 4. Out of scope

- New chart types or new interactions.
- A server-side change.
