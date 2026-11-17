import { Controller } from "@hotwired/stimulus";
import { cssColor } from "../lib/css_color";
import { bridgeShortGaps, chartHalfWindowMetres, smoothSeriesValues } from "../lib/chart_smoothing";
import { PACE_STEPS, niceScale, robustExtent } from "../lib/chart_scale";
import { formatNumber } from "../lib/number_format";
import { weatherPillUrl } from "../lib/weather_icons";
import { ANOMALY_INSPECT_EVENT, anomalyInspecting } from "../lib/anomaly_inspect";
import { loadECharts } from "../lib/charts/echarts";
import { mountChart } from "../lib/charts/lifecycle";
import { chartFont, withAlpha } from "../lib/charts/theme";
import { tooltipBase } from "../lib/charts/tooltip";

const METRES_PER_KILOMETRE = 1000;
const METRES_PER_MILE = 1609.344;
const METRES_PER_FOOT = 0.3048;
const TOPONYMY_MAX_POLLS = 120;
const TOPONYMY_MAX_POLL_DELAY = 15_000;
// Chart pictograms: climbs and descents both mark summits, so only the summit
// and the pause glyph are drawn for them; the weather tab marks each change of
// weather with its condition icon (docs/dev/WEATHER.md).
const TABLER_GLYPHS = {
  mountain: "\u{ef97}",
  stop: "\u{ed45}",
  sun: "\u{eb30}",
  "sun-low": "\u{f237}",
  cloud: "\u{ea76}",
  "cloud-fog": "\u{ecd9}",
  droplet: "\u{ea97}",
  "cloud-rain": "\u{ea72}",
  umbrella: "\u{ebf1}",
  snowflake: "\u{ec0b}",
  "cloud-snow": "\u{ea73}",
  "cloud-storm": "\u{ea74}",
};
// Vertical pixel offset applied to a crowded analysis pictogram, above or
// below the curve. Place numbers never move (DESIGN.md §15.1).
const ICON_OFFSET = 15;

// Hover position is exchanged with the map as a distance along the workout, in
// metres. Not a point index: the public chart endpoint bounds its response to
// 1,000 points and omits indexes entirely, so only distance is common to both
// sides for every viewer.
const TRACK_HOVER = "allure:track-hover";

// The hover cursor: a 1px dotted rule and a 12px ball, drawn as one graphic
// layer whichever side (the chart pointer or the map) moves it.
const HOVER_LINE_COLOR = "#b6b6b6";
const HOVER_LINE_DASH = 3;
const HOVER_BALL_RADIUS = 5;
// A place or pictogram names itself in the reading tooltip while the pointer
// is this close to it, in pixels.
const MARKER_HOVER_PX = 10;

// Touch range selection: a press held this long without moving starts a
// selection drag instead of a page scroll (the mouse drags right away).
const TOUCH_SELECT_DELAY = 350;
const TOUCH_SELECT_SLOP = 8;

// The plot's insets in pixels, so its rectangle is the container minus them
// and every HTML overlay (distance ticks, top axis values, anomaly dashes,
// touch selection) is placed without reading the library's internals. The y
// axes float over the plot instead of reserving a label column: their labels
// are hidden and #drawAxisLabels writes only the top value, with its unit,
// inside the plot's top corners. Under the plot: the distance ticks' row,
// then the axis title, then the legend when two series are drawn.
const GRID_SIDE = 4;
const GRID_TOP = 8;
const X_TICK_ROW = 22;
const X_TITLE_ROW = 20;
const LEGEND_ROW = 26;
// Every marker (places, pictograms, laps, focus band) rides on the series the
// viewer reads: the elevation profile, or the secondary line drawn alone.
const ANCHOR_SERIES = "anchor";

// The chart payload marks a recording gap with a point that carries no
// reading at all; numbering the runs between those markers lets the display
// bridge a sensor's short holes without ever joining two recording segments.
const READING_KEYS = ["elevation", "speed", "heart_rate", "cadence", "power", "device_temperature"];

// Flagged readings (owner-only, DESIGN.md §15.5) are short dashes along the
// foot of the plot, one row per kind of reading so a heart-rate dropout never
// hides a GPS jump at the same place. A one-point finding stays this wide.
const ANOMALY_ROWS = { gps: 0, time: 0, heart_rate: 1, elevation: 2, power: 3, cadence: 3 };
const ANOMALY_ROW_SPACING = 6;
const ANOMALY_FOOT_INSET = 5;
const ANOMALY_MIN_WIDTH = 6;

const escapeHtml = (text) => String(text ?? "").replace(/[&<>"']/g, (char) => `&#${char.charCodeAt(0)};`);

function recordingRuns(points) {
  let run = 0;
  return points.map((point) => {
    if (READING_KEYS.every((key) => !Number.isFinite(point[key]))) run += 1;
    return run;
  });
}

export default class extends Controller {
  static targets = [
    "chart", "loading", "error", "empty", "secondaryMetric",
    "routeContext", "toponymyState", "places", "placesList",
    "zoomReset", "touchSelection", "xTicks", "anomalies", "photos",
  ];

  static values = {
    url: String,
    toponymyUrl: String,
    selectionUrl: String,
    selection: { type: Boolean, default: false },
    unitSystem: { type: String, default: "metric" },
    // "distance" for every workout with a track; "time" for a positionless
    // recording whose file recorded no distance at all (docs/dev/NO-GPS.md):
    // the x axis then reads elapsed minutes, never a row of zeros.
    axisMode: { type: String, default: "distance" },
    // A power-led virtual ride opens on its watts, and keeps its own stored
    // choice (docs/dev/VIRTUAL-PLATFORMS.md).
    powerLed: { type: Boolean, default: false },
    distanceLabel: String,
    elevationLabel: String,
    elapsedTimeLabel: String,
    minuteLabel: String,
    speedLabel: String,
    paceLabel: String,
    paceBasis: String,
    paceBasisLabel: String,
    heartRateLabel: String,
    cadenceLabel: String,
    powerLabel: String,
    kilometreLabel: String,
    mileLabel: String,
    passLabel: String,
    summitLabel: String,
    toponymyLoadingLabel: String,
    toponymyErrorLabel: String,
    startLabel: String,
    finishLabel: String,
    loopLabel: String,
    loopEndpointLabel: String,
    metreLabel: String,
    footLabel: String,
    kilometresPerHourLabel: String,
    milesPerHourLabel: String,
    heartRateUnit: String,
    cadenceUnit: String,
    powerUnit: String,
    // Weather channels (docs/dev/WEATHER.md), stored in °C and m/s.
    temperatureLabel: String,
    deviceTemperatureLabel: String,
    headwindLabel: String,
    celsiusUnit: String,
    fahrenheitUnit: String,
    anomalies: { type: Array, default: [] },
    // The owner's placed photos (docs/dev/PHOTOS.md): id, distance, label.
    photos: { type: Array, default: [] },
  };

  connect() {
    this.connected = true;
    this.chart = null;
    this.mounted = null;
    this.markers = [];
    this.boundaries = [];
    this.analysisMarkers = [];
    this.analysisSteps = [];
    this.activeTab = null;
    this.focusRange = null;
    this.focusSource = null;
    this.focusLabel = null;
    this.hoverDistance = null;
    this.iconOffsets = null;
    this.anchorSeries = null;
    this.anchorReversed = false;
    this.axisMin = null;
    this.axisMax = null;
    this.markerGap = 0;
    this.zoomed = false;
    this.abortController = new AbortController();
    // Bootstrap tooltips for the anomaly dashes, created on first hover and
    // reused while the marks live: an inspected recording can hold many.
    this.anomalyTooltips = new Map();
    this.mobileMedia = window.matchMedia("(max-width: 575.98px)");
    this.breakpointChanged = () => this.#breakpointChanged();
    this.mobileMedia.addEventListener("change", this.breakpointChanged);
    // Only the findings that change a figure show until the owner inspects
    // every one from the data quality tab.
    this.inspectAnomalies = anomalyInspecting();
    this.anomalyInspectChanged = (event) => {
      this.inspectAnomalies = Boolean(event.detail?.inspect);
      this.#drawAnomalies();
    };
    window.addEventListener(ANOMALY_INSPECT_EVENT, this.anomalyInspectChanged);
    this.#restoreSecondaryMetric();
    this.#showState("loading");
    this.#load();
    if (this.hasToponymyUrlValue) this.#loadToponymy();
  }

  disconnect() {
    this.connected = false;
    this.renderGeneration = (this.renderGeneration || 0) + 1;
    this.abortController?.abort();
    if (this.toponymyTimer) clearTimeout(this.toponymyTimer);
    this.mobileMedia?.removeEventListener("change", this.breakpointChanged);
    window.removeEventListener(ANOMALY_INSPECT_EVENT, this.anomalyInspectChanged);
    this.#disposeAnomalyTooltips();
    if (this.hoverFrame) cancelAnimationFrame(this.hoverFrame);
    this.#releaseTouchSelection();
    if (this.zoomRedraw) cancelAnimationFrame(this.zoomRedraw);
    this.zoomRedraw = null;
    this.mounted?.release();
    this.mounted = null;
    this.chart = null;
    this.abortController = null;
    this.points = null;
    this.markers = null;
    this.boundaries = null;
    this.analysisMarkers = null;
    this.analysisSteps = null;
    this.activeTab = null;
    this.focusRange = null;
    this.focusSource = null;
    this.focusLabel = null;
    this.hoverFrame = null;
    this.hoverDistance = null;
    this.iconOffsets = null;
    this.anchorSeries = null;
    this.axisMin = null;
    this.axisMax = null;
    this.routeContext = null;
    this.anomalyTooltips = null;
  }

  // The y-axis tick count follows the viewport, so crossing the breakpoint
  // rebuilds the chart instead of only redrawing its annotations.
  #breakpointChanged() {
    this.#recreate();
  }

  async #recreate() {
    if (!this.points) return;

    this.mounted?.release();
    this.mounted = null;
    this.chart = null;
    try {
      await this.#render(this.points);
    } catch {
      if (this.connected) this.#showState("error");
    }
  }

  // The map publishes where the pointer is on the route; mark the matching
  // place on the profile. The cursor is its own layer, so moving it never
  // redraws the markers.
  trackHover(event) {
    if (!this.chart || event.detail?.source === "chart") return;

    const distance = event.detail?.clear ? null : event.detail?.distance;
    this.#setHover(Number.isFinite(distance) ? distance : null);
  }

  // The chart's own pointer sets the same cursor state the map drives, so the
  // ball and the dotted rule appear whichever side the pointer is on.
  #chartPointerMoved(index) {
    const point = Number.isInteger(index) && index >= 0 ? this.points?.[index] : null;
    this.#setHover(point && Number.isFinite(point.distance) ? point.distance : null);
    this.#publishHover(index);
  }

  // Pointer moves arrive far faster than the chart can usefully redraw, so the
  // cursor is redrawn once per frame. Shared by the map and the chart pointer.
  #setHover(distance) {
    if (distance === this.hoverDistance) return;

    this.hoverDistance = distance;
    if (this.hoverFrame) cancelAnimationFrame(this.hoverFrame);
    this.hoverFrame = requestAnimationFrame(() => {
      this.hoverFrame = null;
      if (!this.chart) return;

      this.#redrawCursor();
    });
  }

  // Numeric selection fields are the keyboard equivalent of the chart brush:
  // they set the brushed band (a programmatic brush raises no brushEnd, so
  // the fields are not echoed back). The map and the server still own the
  // authoritative geometry validation.
  selectionInputChanged(event) {
    if (!this.selectionValue || !this.chart) return;

    if (event.detail?.clear) {
      this.chart.dispatchAction({ type: "brush", areas: [] });
      return;
    }

    const startIndex = Number(event.detail?.startIndex);
    const endIndex = Number(event.detail?.endIndex);
    if (!(endIndex > startIndex)) return;
    // The plotted profile is bounded to 1,000 points, so a typed index lands
    // on the nearest plotted one.
    const start = this.#pointNearIndex(startIndex);
    const end = this.#pointNearIndex(endIndex);
    if (!start || !end || end.distance <= start.distance) return;

    this.chart.dispatchAction({
      type: "brush",
      areas: [{
        brushType: "lineX",
        xAxisIndex: 0,
        coordRange: [start.distance / this.distanceDivisor, end.distance / this.distanceDivisor],
      }],
    });
  }

  #pointNearIndex(index) {
    let best = null;
    for (const point of this.points ?? []) {
      if (!Number.isInteger(point.index)) continue;
      if (!best || Math.abs(point.index - index) < Math.abs(best.index - index)) best = point;
    }
    return best;
  }

  // The focus band first (background), then the dashed boundaries, the
  // smart-lap pictograms and the persistent toponymic markers; the transient
  // hover cursor is a graphic layer of its own, redrawn on every pointer
  // frame without touching these. The layers strictly follow the active tab:
  // toponymy places are always there, summits only through the climbs tab
  // markers, stops through the stops tab markers. Every marker sits on the
  // drawn curve; only the analysis pictograms move off it when they crowd.
  #redrawAnnotations() {
    if (!this.chart || this.chart.isDisposed()) return;

    this.iconOffsets = this.#iconOffsets();
    this.chart.setOption({
      series: [{
        id: ANCHOR_SERIES,
        markArea: this.#focusArea(),
        markLine: this.#boundaryLines(),
        markPoint: {
          animation: false,
          data: [...this.#analysisPoints(), ...this.#stopPanel(), ...this.#placePoints()],
        },
      }],
    });
    this.#redrawCursor();
  }

  // The same ball as the map cursor, on the anchor curve: ink fill and a page
  // ring, 12px across like the map marker, over the dotted rule.
  #redrawCursor() {
    const chart = this.chart;
    if (!chart || chart.isDisposed()) return;

    const geometry = this.#plotGeometry();
    const value = this.hoverDistance === null ? null : this.hoverDistance / this.distanceDivisor;
    const shown = Boolean(geometry) && value !== null && value >= geometry.minX && value <= geometry.maxX;
    const x = shown ? chart.convertToPixel({ xAxisIndex: 0 }, value) : 0;
    const y = shown ? this.#curveYAt(this.hoverDistance) : null;
    const cy = y === null ? 0 : chart.convertToPixel({ seriesId: ANCHOR_SERIES }, [value, y])[1];
    // Two fixed elements, updated in place and hidden between hovers.
    chart.setOption({
      graphic: [
        {
          id: "cursor-rule",
          type: "line",
          silent: true,
          z: 100,
          invisible: !shown,
          shape: { x1: x, y1: geometry?.top ?? 0, x2: x, y2: (geometry?.top ?? 0) + (geometry?.height ?? 0) },
          style: { stroke: HOVER_LINE_COLOR, lineWidth: 1, lineDash: [HOVER_LINE_DASH, HOVER_LINE_DASH] },
        },
        {
          id: "cursor-ball",
          type: "circle",
          silent: true,
          z: 101,
          invisible: !shown || y === null,
          shape: { cx: x, cy, r: HOVER_BALL_RADIUS },
          style: { fill: this.#foregroundColor(), stroke: this.#pageColor(), lineWidth: 2 },
        },
      ],
    });
  }

  #placePoints() {
    return (this.markers ?? []).map((marker) => ({
      coord: [marker.distance / this.distanceDivisor, this.#anchorY(marker, marker.elevation)],
      symbol: "circle",
      symbolSize: 16,
      itemStyle: { color: this.#surfaceColor(), borderColor: this.#mutedColor(), borderWidth: 2 },
      label: {
        show: true,
        position: "inside",
        formatter: () => String(marker.rank),
        color: this.#foregroundColor(),
        fontSize: 10,
        fontWeight: 700,
      },
      emphasis: { disabled: true },
    }));
  }

  #focusArea() {
    // A heart-rate zone shades every stretch where it was ridden.
    const ranges = this.focusRange ? (this.focusRange.ranges ?? [ this.focusRange ]) : [];
    const data = ranges.flatMap(({ start, end }) => {
      const x = start / this.distanceDivisor;
      const x2 = end / this.distanceDivisor;
      return Number.isFinite(x) && Number.isFinite(x2) && x2 > x ? [[{ xAxis: x }, { xAxis: x2 }]] : [];
    });
    if (!data.length) return { data: [] };

    // The theme ink, like the map's highlighted slice: the profile itself is
    // primary, so a primary band would barely stand out from it.
    return {
      silent: true,
      animation: false,
      itemStyle: { color: this.#foregroundColor(), opacity: 0.14 },
      data,
    };
  }

  #boundaryLines() {
    const data = (this.boundaries ?? []).flatMap((boundary) => {
      const x = Number(boundary.distance) / this.distanceDivisor;
      if (!Number.isFinite(x)) return [];

      const text = boundary.label === null || boundary.label === undefined ? null : String(boundary.label);
      return [{
        xAxis: x,
        label: text === null ? { show: false } : {
          show: true,
          position: "insideEndTop",
          formatter: () => text,
          color: this.#foregroundColor(),
          backgroundColor: this.#surfaceColor(),
          padding: [1, 3],
          fontSize: 11,
          fontWeight: 600,
        },
      }];
    });
    return {
      silent: true,
      animation: false,
      symbol: ["none", "none"],
      lineStyle: { color: this.#mutedColor(), width: 1, type: [4, 4] },
      label: { show: false },
      emphasis: { disabled: true },
      data,
    };
  }

  // The pill is the marker itself, the same 16px size as a place number.
  // symbolOffset carries the crowding offset while the anchor stays on the
  // curve. A weather marker draws the white Meteocons icon, animated unless
  // the reader asked for less motion, on the same brand-primary pill as the
  // other tabs' glyphs (docs/dev/WEATHER.md).
  #analysisPoints() {
    return (this.analysisMarkers ?? []).flatMap((marker) => {
      const distance = Number(marker.distance);
      const x = distance / this.distanceDivisor;
      if (!Number.isFinite(x)) return [];

      const offsetY = this.iconOffsets?.get(marker) ?? 0;
      if (marker.svg) return [ this.#weatherPill(marker, distance, offsetY) ];

      const glyph = TABLER_GLYPHS[marker.glyph] ?? TABLER_GLYPHS.mountain;
      const emphasized = marker.glyph === "stop" &&
        this.focusSource === "stop" &&
        this.focusRange !== null &&
        Math.abs(distance - this.focusRange.start) <= 1;
      return [{
        coord: [x, this.#anchorY(marker)],
        symbol: "circle",
        symbolSize: emphasized ? 20 : 16,
        symbolOffset: [0, offsetY],
        itemStyle: { color: this.#primaryColor(), borderColor: this.#surfaceColor(), borderWidth: 2 },
        // The glyph reads on the rose pill in both themes.
        label: {
          show: true,
          position: "inside",
          formatter: () => glyph,
          color: "#ffffff",
          fontFamily: "tabler-icons",
          fontSize: emphasized ? 12 : 10,
          fontWeight: 400,
        },
        emphasis: { disabled: true },
      }];
    });
  }

  #weatherPill(marker, distance, offsetY) {
    const url = weatherPillUrl(marker.svg, {
      background: this.#primaryColor(),
      border: this.#surfaceColor(),
      color: "#ffffff",
      size: 48,
      // The drawing fills about two thirds of its square.
      iconRatio: 0.92,
    });
    return {
      coord: [ distance / this.distanceDivisor, this.#anchorY(marker) ],
      symbol: `image://${url}`,
      symbolSize: 21,
      symbolOffset: [0, offsetY],
      emphasis: { disabled: true },
    };
  }

  // The hovered or pinned stop only adds its duration panel: the pill is
  // already drawn, enlarged, by #analysisPoints, so never draw a second one
  // here.
  #stopPanel() {
    if (this.focusSource !== "stop" || !this.focusRange || !this.focusLabel) return [];

    const distance = this.focusRange.start;
    const x = distance / this.distanceDivisor;
    if (!Number.isFinite(x)) return [];

    const stop = (this.analysisMarkers ?? []).find((marker) =>
      marker.glyph === "stop" && Math.abs(Number(marker.distance) - distance) <= 1);
    const offsetY = stop ? (this.iconOffsets?.get(stop) ?? 0) : 0;
    const text = String(this.focusLabel);
    return [{
      coord: [x, stop ? this.#anchorY(stop) : this.#anchorY({ distance })],
      symbol: "circle",
      symbolSize: 0,
      symbolOffset: [0, offsetY],
      silent: true,
      label: {
        show: true,
        position: "top",
        distance: 16,
        formatter: () => text,
        color: "#ffffff",
        backgroundColor: this.#primaryColor(),
        borderRadius: 3,
        padding: [2, 6],
        fontSize: 11,
        fontWeight: 600,
      },
      emphasis: { disabled: true },
    }];
  }

  // The names of the places and pictograms under the pointer, for the
  // reading tooltip: on the plot their pills only carry a number or a glyph.
  #markerNamesNear(xValue) {
    const geometry = this.#plotGeometry();
    if (!geometry || !Number.isFinite(xValue)) return [];

    const tolerance = (MARKER_HOVER_PX / geometry.width) * (geometry.maxX - geometry.minX);
    const near = (distance) => Math.abs(Number(distance) / this.distanceDivisor - xValue) <= tolerance;
    return [
      ...(this.markers ?? []).filter((marker) => near(marker.distance)).map((marker) => marker.name),
      ...(this.analysisMarkers ?? []).filter((marker) => near(marker.distance))
        .map((marker) => [marker.name, marker.label].filter(Boolean).join(" · "))
        .filter(Boolean),
    ];
  }

  // The laps card broadcasts the active tab's chart data as distances in
  // metres: dashed boundaries, pictogram markers, and the route-step entries
  // that share the same tab.
  analysisTabChanged(event) {
    const boundaries = Array.isArray(event.detail?.boundaries) ? event.detail.boundaries : [];
    const markers = Array.isArray(event.detail?.markers) ? event.detail.markers : [];
    const steps = Array.isArray(event.detail?.steps) ? event.detail.steps : [];
    this.activeTab = event.detail?.id ?? null;
    this.boundaries = boundaries.filter((boundary) => Number.isFinite(Number(boundary?.distance)));
    this.analysisMarkers = markers.filter((marker) => Number.isFinite(Number(marker?.distance)));
    this.analysisSteps = steps.filter((step) => Number.isFinite(Number(step?.distance)));
    this.#redrawAnnotations();
    this.#renderMarkerList();
  }

  // A lap row broadcasts its distance range while hovered, focused, or pinned.
  // The range is drawn as a translucent band under the boundaries, pictograms,
  // and the hover cursor; a stop also gets its duration panel.
  analysisHighlightChanged(event) {
    const start = Number(event.detail?.startDistance);
    const end = Number(event.detail?.endDistance);
    const clear = event.detail?.clear || !Number.isFinite(start) || !Number.isFinite(end) || end <= start;
    const ranges = Array.isArray(event.detail?.ranges) ? event.detail.ranges : null;
    this.focusRange = clear ? null : { start, end, ranges };
    this.focusSource = clear ? null : (event.detail?.source ?? null);
    this.focusLabel = clear ? null : (event.detail?.label ?? null);
    this.#redrawAnnotations();
  }

  // Text equivalent of the markers (DESIGN §15.1): names are OSM-sourced, so
  // they are inserted as text nodes, never HTML.
  #renderToponymy() {
    this.#renderRouteContext();
    this.#renderMarkerList();
    this.#redrawAnnotations();
  }

  #renderRouteContext() {
    if (!this.hasRouteContextTarget) return;

    const start = this.routeContext?.start?.name;
    const finish = this.routeContext?.finish?.name;
    const loop = this.routeContext?.loop === true;
    this.routeContextTarget.hidden = !start && !finish;
    this.routeContextTarget.textContent = loop && start
      ? `${this.loopLabelValue} ${start}`
      : start && finish ? `${start} → ${finish}` : start || finish || "";
  }

  // The route timeline: start/finish context and toponymy places, always,
  // interleaved with the active tab's own steps. Place buttons move the point
  // cursor; tab steps preview their whole range on the chart and the map.
  #renderMarkerList() {
    if (!this.hasPlacesTarget || !this.hasPlacesListTarget) return;

    const start = this.routeContext?.start?.name;
    const finish = this.routeContext?.finish?.name;
    const loop = this.routeContext?.loop === true;
    const places = [...(this.markers ?? [])].sort((a, b) => a.distance - b.distance);
    const totalDistance = this.points?.at(-1)?.distance || places.at(-1)?.distance || 0;
    const steps = [
      ...(start ? [{ type: "place", name: start, distance: 0, endpoint: loop ? this.loopEndpointLabelValue : this.startLabelValue }] : []),
      ...places.map((place) => ({ type: "place", ...place })),
      ...(this.analysisSteps ?? []).map((step) => ({ type: "step", ...step })),
      ...(finish && !loop ? [{ type: "place", name: finish, distance: totalDistance, endpoint: this.finishLabelValue }] : []),
    ].sort((a, b) => a.distance - b.distance);

    this.placesTarget.hidden = steps.length === 0;
    this.placesListTarget.replaceChildren();
    if (this.placesTarget.hidden) return;

    for (const entry of steps) {
      const item = document.createElement("li");
      item.className = "allure-route-timeline__step";
      item.append(entry.type === "step" ? this.#buildStepButton(entry) : this.#buildPlaceButton(entry));
      this.placesListTarget.append(item);
    }
  }

  #buildPlaceButton(place) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "allure-route-timeline__button";
    button.dataset.distance = place.distance;
    button.addEventListener("mouseenter", (event) => this.placeFocus(event));
    button.addEventListener("mouseleave", () => this.placeBlur());
    button.addEventListener("focus", (event) => this.placeFocus(event));
    button.addEventListener("blur", () => this.placeBlur());
    button.addEventListener("click", (event) => this.placeFocus(event));

    const dot = document.createElement("span");
    dot.className = "allure-route-timeline__dot";
    dot.setAttribute("aria-hidden", "true");
    dot.textContent = place.rank || "";
    const name = document.createElement("span");
    name.className = "allure-route-timeline__name";
    name.textContent = place.name;
    const detail = document.createElement("span");
    detail.className = "allure-route-timeline__detail";
    const imperial = this.unitSystemValue === "imperial";
    const divisor = imperial ? METRES_PER_MILE : METRES_PER_KILOMETRE;
    const unit = imperial ? this.mileLabelValue : this.kilometreLabelValue;
    const kind = ["pass", "summit"].includes(place.kind)
      ? (place.kind === "pass" ? this.passLabelValue : this.summitLabelValue)
      : place.endpoint;
    detail.textContent = place.endpoint
      ? place.endpoint
      : `${formatNumber(place.distance / divisor, 1)} ${unit}${kind ? ` · ${kind}` : ""}`;
    button.append(dot, name, detail);
    return button;
  }

  #buildStepButton(step) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "allure-route-timeline__button allure-route-timeline__button--step";
    button.addEventListener("mouseenter", () => this.stepPreview(step));
    button.addEventListener("mouseleave", () => this.stepPreview(null));
    button.addEventListener("focus", () => this.stepPreview(step));
    button.addEventListener("blur", () => this.stepPreview(null));
    button.addEventListener("click", () => this.stepPreview(step));

    const dot = document.createElement("span");
    dot.className = "allure-route-timeline__dot allure-route-timeline__dot--step";
    dot.setAttribute("aria-hidden", "true");
    if (typeof step.icon === "string" && /^[a-z0-9-]+$/.test(step.icon)) {
      const glyph = document.createElement("i");
      glyph.className = `ti ti-${step.icon}`;
      dot.append(glyph);
    }
    const name = document.createElement("span");
    name.className = "allure-route-timeline__name";
    name.textContent = step.name;
    const detail = document.createElement("span");
    detail.className = "allure-route-timeline__detail";
    detail.textContent = [ step.sourceLabel, step.detail ].filter(Boolean).join(" · ");
    button.append(dot, name, detail);
    return button;
  }

  // Previewed through the laps card so a pinned row wins again on blur; this
  // controller only draws whatever range the card publishes.
  stepPreview(step) {
    window.dispatchEvent(new CustomEvent("allure:analysis-step-preview", {
      detail: step
        ? {
          startDistance: Number(step.distance),
          endDistance: Number(step.endDistance),
          source: step.source ?? null,
          label: step.detail ?? null,
        }
        : { clear: true },
    }));
  }

  placeFocus(event) {
    const distance = Number(event.currentTarget?.dataset?.distance);
    if (!Number.isFinite(distance)) return;

    window.dispatchEvent(new CustomEvent(TRACK_HOVER, { detail: { source: "toponymy", distance } }));
  }

  placeBlur() {
    window.dispatchEvent(new CustomEvent(TRACK_HOVER, { detail: { source: "toponymy", clear: true } }));
  }

  #validMarker(entry) {
    if (!entry || typeof entry !== "object") return null;

    const distance = Number(entry.distance);
    const name = typeof entry.name === "string" ? entry.name.trim().slice(0, 80) : "";
    const elevation = Number(entry.elevation);
    const rank = Number(entry.rank);
    const kind = typeof entry.kind === "string" ? entry.kind : "";
    const kinds = [
      "pass", "summit", "landmark", "route", "viewpoint", "waterfall", "spring", "cave", "city", "town",
      "village", "hut", "hamlet", "locality", "isolated_dwelling", "municipality", "suburb",
      "neighbourhood",
    ];
    if (!Number.isFinite(distance) || !Number.isInteger(rank) || name === "" || !kinds.includes(kind)) return null;

    return { distance, elevation: Number.isFinite(elevation) ? elevation : null, name, kind, rank };
  }

  #mutedColor() {
    return cssColor("--secondary", "#667382");
  }

  #surfaceColor() {
    return cssColor("--allure-surface-raised", "#ffffff");
  }

  // The map hover ball's ring is the page background; the chart cursor uses the
  // same token so both read as the same object.
  #pageColor() {
    return cssColor("--body-bg", "#ffffff");
  }

  // Every colour comes from the page's tokens, resolved when the chart is
  // built: a theme change rebuilds it.
  async themeChanged() {
    await this.#recreate();
  }

  async secondaryMetricChanged() {
    this.#storeSecondaryMetric();
    await this.#recreate();
  }

  async #load() {
    try {
      const url = this.selectionValue && this.hasSelectionUrlValue ? this.selectionUrlValue : this.urlValue;
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: this.abortController.signal,
      });
      if (!response.ok) throw new Error(`Chart request failed with ${response.status}`);

      const data = await response.json();
      if (!Array.isArray(data?.points)) throw new Error("Invalid chart response");
      const selectedMetric = this.#selectedSecondaryMetric();
      const hasElevation = data.points.some((point) => this.#numericValue(point.elevation) !== null);
      const hasSecondary = selectedMetric && data.points.some((point) => this.#rawSecondaryValue(point, selectedMetric) !== null);
      if (!this.selectionValue && !hasElevation && !hasSecondary) {
        this.#showState("empty");
        return;
      }

      if (this.connected) await this.#render(data.points);
    } catch (error) {
      if (error.name !== "AbortError" && this.connected) this.#showState("error");
    }
  }

  async #loadToponymy(attempt = 0) {
    try {
      const response = await fetch(this.toponymyUrlValue, {
        headers: { Accept: "application/json" },
        signal: this.abortController.signal,
      });
      if (!response.ok) throw new Error(`Toponymy request failed with ${response.status}`);

      const data = await response.json();
      if (data?.status === "pending") {
        if (attempt >= TOPONYMY_MAX_POLLS) {
          this.#showToponymyState("error");
          return;
        }

        this.#showToponymyState("loading");
        const delay = Math.min(1_000 * (2 ** Math.floor(attempt / 10)), TOPONYMY_MAX_POLL_DELAY);
        this.toponymyTimer = setTimeout(() => this.#loadToponymy(attempt + 1), delay);
        return;
      }
      if (data?.status !== "ready" && data?.status !== "partial") {
        this.#showToponymyState(data?.status === "failed" ? "error" : "hidden");
        return;
      }

      this.routeContext = { start: data.start, finish: data.finish, loop: data.loop === true };
      this.markers = Array.isArray(data.markers)
        ? data.markers.map((entry) => this.#validMarker(entry)).filter(Boolean)
        : [];
      this.#showToponymyState("ready");
      this.#renderToponymy();
    } catch (error) {
      if (error.name !== "AbortError" && this.connected) this.#showToponymyState("error");
    }
  }

  #showToponymyState(state) {
    if (!this.hasToponymyStateTarget) return;

    this.toponymyStateTarget.hidden = state === "ready" || state === "hidden";
    this.toponymyStateTarget.textContent = state === "loading"
      ? this.toponymyLoadingLabelValue
      : this.toponymyErrorLabelValue;
  }

  async #render(points) {
    const generation = (this.renderGeneration || 0) + 1;
    this.renderGeneration = generation;
    const imperial = this.unitSystemValue === "imperial";
    const distanceDivisor = imperial ? METRES_PER_MILE : METRES_PER_KILOMETRE;
    const elevationDivisor = imperial ? METRES_PER_FOOT : 1;
    const distanceUnit = imperial ? this.mileLabelValue : this.kilometreLabelValue;
    const elevationUnit = imperial ? this.footLabelValue : this.metreLabelValue;
    const timeAxis = this.axisModeValue === "time";
    // The x value of one plotted point: elapsed minutes on a time axis, the
    // traveller's distance otherwise.
    const xOf = (point) => (timeAxis ? (point.elapsed_time ?? 0) / 60 : point.distance / distanceDivisor);
    const totalDistance = points.at(-1)?.distance / distanceDivisor;
    const spanMax = timeAxis ? xOf(points.at(-1) ?? {}) : totalDistance;
    const distanceMax = Number.isFinite(spanMax) && spanMax > 0 ? spanMax : undefined;
    this.markerGap = timeAxis ? 0 : (points.at(-1)?.distance ?? 0) * 0.04;
    const secondaryMetric = this.#selectedSecondaryMetric();
    const secondary = secondaryMetric ? this.#secondaryDescriptor(secondaryMetric, imperial) : null;
    this.points = points;
    this.distanceDivisor = distanceDivisor;
    this.elevationDivisor = elevationDivisor;
    this.timeAxis = timeAxis;
    const elevationData = points.map((point) => {
      const elevation = this.#numericValue(point.elevation);
      return {
        x: xOf(point),
        y: elevation === null ? (this.selectionValue ? 0 : null) : elevation / elevationDivisor,
        elapsedTime: point.elapsed_time,
        index: point.index,
        segmentIndex: point.segment_index,
      };
    });
    const elevations = elevationData.map((point) => point.y).filter((value) => value !== null);
    const primary = this.#primaryColor();
    const muted = this.#mutedColor();
    const foreground = this.#foregroundColor();
    const border = cssColor("--border-color", "#dce1e7");
    const chartSeries = [];
    const yAxes = [];
    const axisLabels = [];
    let axisMin = null;
    let axisMax = null;
    let plottedSecondary = null;
    const hiddenAxis = { axisLabel: { show: false }, axisLine: { show: false }, axisTick: { show: false } };
    const gridLines = { show: true, lineStyle: { color: border, type: [3, 3] } };
    const hasSecondary = secondary && points.some((point) => secondary.raw(point) !== null);
    if (elevations.length > 0) {
      const scale = niceScale(Math.min(...elevations), Math.max(...elevations), this.#yAxisTickAmount());
      axisMin = scale.min;
      axisMax = scale.max;
      chartSeries.push({
        id: ANCHOR_SERIES,
        name: `${this.elevationLabelValue} (${elevationUnit})`,
        type: "line",
        yAxisIndex: 0,
        data: elevationData.map((point) => [point.x, point.y]),
        color: primary,
        lineStyle: { color: primary, width: 2 },
        areaStyle: {
          color: {
            type: "linear", x: 0, y: 0, x2: 0, y2: 1,
            colorStops: [{ offset: 0, color: withAlpha(primary, 0.4) }, { offset: 1, color: withAlpha(primary, 0.05) }],
          },
        },
        z: 2,
      });
      yAxes.push({ type: "value", min: scale.min, max: scale.max, interval: scale.step, ...hiddenAxis, splitLine: gridLines });
      axisLabels.push({ side: "start", text: `${formatNumber(scale.max)} ${elevationUnit}` });
    }
    if (hasSecondary) {
      const secondaryData = this.#secondarySeriesData(points, secondary, distanceDivisor, points.at(-1)?.distance, xOf);
      const secondaryValues = secondaryData.map((point) => point.y).filter((value) => value !== null);
      if (secondaryValues.length > 0) {
        plottedSecondary = secondaryData;
        // Bounded on the bulk of the readings: one stop must not squash a
        // pace line against the edge, and an axis never starts at 0:00.
        const [low, high] = robustExtent(secondaryValues);
        const scale = secondaryMetric === "pace"
          ? niceScale(low, high, this.#yAxisTickAmount(), PACE_STEPS)
          : niceScale(low, high, this.#yAxisTickAmount());
        const alone = elevations.length === 0;
        if (axisMin === null) {
          axisMin = scale.min;
          axisMax = scale.max;
        }
        // The secondary line is a muted, thin, slightly transparent trend
        // under the profile, never a dashed pattern: dashes broke a noisy
        // line into unreadable specks. Without an elevation profile it is
        // the figure itself, in primary.
        const color = alone ? primary : muted;
        chartSeries.push({
          id: alone ? ANCHOR_SERIES : "secondary",
          name: secondary.axisTitle,
          type: "line",
          yAxisIndex: yAxes.length,
          data: secondaryData.map((point) => [point.x, point.y]),
          color,
          lineStyle: { color, width: alone ? 2 : 1.25, opacity: alone ? 1 : 0.75 },
          z: 3,
        });
        yAxes.push({
          type: "value",
          position: alone ? "left" : "right",
          inverse: secondaryMetric === "pace",
          min: scale.min,
          max: scale.max,
          interval: scale.step,
          ...hiddenAxis,
          splitLine: alone ? gridLines : { show: false },
        });
        // A reversed pace axis reads its fastest value at the top.
        const top = secondaryMetric === "pace" ? secondary.axisFormatter(scale.min) : formatNumber(scale.max);
        axisLabels.push({ side: alone ? "start" : "end", text: `${top} ${secondary.unit}`.trim() });
      }
    }

    if (chartSeries.length === 0) {
      this.#showState("empty");
      return;
    }
    this.axisLabels = axisLabels;
    // Markers anchor on what the viewer sees: the elevation profile when it is
    // drawn, the secondary line otherwise. The axis extent only chooses which
    // way a crowded pictogram moves first.
    this.anchorSeries = elevations.length > 0 ? elevationData : plottedSecondary;
    this.anchorReversed = elevations.length === 0 && secondaryMetric === "pace";
    this.axisMin = axisMin;
    this.axisMax = axisMax;
    this.xValues = (this.anchorSeries ?? elevationData).map((point) => point.x);
    // The legend carries each series' name and unit now that the axes have
    // no vertical titles (DESIGN.md §15.1). A lone series has nothing to
    // tell apart: its unit is printed on the axis labels instead.
    const legend = chartSeries.length > 1;
    this.gridBottom = X_TICK_ROW + X_TITLE_ROW + (legend ? LEGEND_ROW : 0);

    const echarts = await loadECharts();
    if (!this.connected || generation !== this.renderGeneration) return;

    this.mounted?.release();
    this.mounted = mountChart(echarts, this.chartTarget, { onResize: () => this.#afterLayout() });
    const chart = this.mounted.chart;
    this.chart = chart;
    chart.setOption({
      animation: false,
      textStyle: { fontFamily: chartFont() },
      grid: { left: GRID_SIDE, right: GRID_SIDE, top: GRID_TOP, bottom: this.gridBottom, outerBoundsMode: "none" },
      legend: legend
        ? { show: true, bottom: 0, selectedMode: false, icon: "roundRect", itemWidth: 12, itemHeight: 8, textStyle: { color: foreground } }
        : { show: false },
      xAxis: {
        type: "value",
        // Exact domain, so the curve ends exactly at the axis edge; the
        // library's own labels stay hidden and #drawAxisLabels writes
        // whole-distance ticks at their true place.
        min: 0,
        ...(distanceMax === undefined ? {} : { max: distanceMax }),
        axisLabel: { show: false },
        axisTick: { show: false },
        axisLine: { show: true, lineStyle: { color: border } },
        splitLine: { show: false },
        name: timeAxis
          ? `${this.elapsedTimeLabelValue} (${this.#minuteLabel()})`
          : `${this.distanceLabelValue} (${distanceUnit})`,
        nameLocation: "middle",
        nameGap: X_TICK_ROW + 4,
        nameTextStyle: { color: foreground },
      },
      yAxis: yAxes,
      series: chartSeries.map((item) => ({
        showSymbol: false,
        symbol: "none",
        connectNulls: false,
        emphasis: { disabled: true },
        ...item,
      })),
      tooltip: tooltipBase({
        trigger: "axis",
        // The cursor is one graphic layer shared by the chart and the map
        // (see #redrawCursor); the library's own pointer stays undrawn.
        axisPointer: { type: "none" },
        formatter: (params) => this.#tooltip(params?.[0]?.dataIndex, {
          elevations, secondary, elevationDivisor, elevationUnit, distanceDivisor, distanceUnit, timeAxis,
        }),
      }),
      ...(this.selectionValue
        ? {
          // The brush is driven from the code alone: no toolbox buttons.
          toolbox: { show: false },
          brush: {
            toolbox: [],
            xAxisIndex: 0,
            brushType: "lineX",
            brushMode: "single",
            transformable: true,
            throttleType: "debounce",
            throttleDelay: 150,
            brushStyle: { color: withAlpha(primary, 0.18), borderColor: primary, borderWidth: 1 },
            outOfBrush: { colorAlpha: 1 },
          },
        }
        : {
          // A drag selects the range to zoom into (fine pointers, through
          // the toolbox's select-zoom); the wheel keeps scrolling the page.
          // The passive inside zoom receives the touch selection and the
          // reset.
          // The toolbox must be shown for its select-zoom to exist; its
          // buttons are empty and sized to nothing, the reset is ours.
          toolbox: {
            show: true,
            itemSize: 0,
            itemGap: 0,
            showTitle: false,
            left: 0,
            top: 0,
            feature: {
              dataZoom: {
                xAxisIndex: 0,
                yAxisIndex: false,
                filterMode: "none",
                icon: { zoom: "path://M0,0", back: "path://M0,0" },
                brushStyle: { color: withAlpha(primary, 0.18), borderColor: primary, borderWidth: 1 },
              },
            },
          },
          dataZoom: [{
            type: "inside",
            id: "zoom",
            xAxisIndex: 0,
            filterMode: "none",
            zoomOnMouseWheel: false,
            moveOnMouseMove: false,
            moveOnMouseWheel: false,
            preventDefaultMouseMove: false,
          }],
        }),
    });
    this.#bindChartEvents(chart, points, distanceDivisor);

    this.#showState("ready");
    this.#setZoomed(false);
    this.#bindTouchSelection();
    this.#renderToponymy();
    this.#afterLayout();
  }

  #tooltip(dataIndex, { elevations, secondary, elevationDivisor, elevationUnit, distanceDivisor, distanceUnit, timeAxis }) {
    const point = this.points?.[dataIndex];
    if (!point) return "";

    const elevationValue = this.#numericValue(point.elevation);
    const elevation = elevationValue === null
      ? "—"
      : `${formatNumber(elevationValue / elevationDivisor)} ${elevationUnit}`;
    const readings = elevations.length > 0
      ? `<strong>${this.elevationLabelValue}: ${elevation}</strong>`
      : "";
    const secondaryReading = secondary
      ? `<span>${secondary.label}: ${secondary.tooltipFormatter(secondary.value(point))}</span>`
      : "";
    // A timestamp-less remote GPX has no elapsed time; omit the row rather
    // than showing a misleading 0:00.
    const elapsedReading = Number.isFinite(point.elapsed_time)
      ? `<span>${this.elapsedTimeLabelValue}: ${this.#formatDuration(point.elapsed_time)}</span>`
      : "";
    // The time axis repeats what the elapsed row already says, so a
    // positionless duration-only recording shows it once.
    const distanceReading = timeAxis
      ? ""
      : `<span>${this.distanceLabelValue}: ${formatNumber(point.distance / distanceDivisor, 2)} ${distanceUnit}</span>`;
    // Place and pictogram names come from OSM and analysis labels: text, not
    // HTML.
    const names = this.#markerNamesNear(this.xValues?.[dataIndex])
      .map((name) => `<span class="allure-chart-tooltip-place">${escapeHtml(name)}</span>`)
      .join("");
    return `<div class="allure-chart-tooltip">
      ${names}
      ${readings}
      ${secondaryReading}
      ${distanceReading}
      ${elapsedReading}
    </div>`;
  }

  #bindChartEvents(chart, points, distanceDivisor) {
    const zr = chart.getZr();
    // The chart pointer drives the same cursor as the map: the nearest
    // plotted point under it, anywhere in the plot.
    zr.on("mousemove", (event) => {
      if (!chart.containPixel("grid", [event.offsetX, event.offsetY])) {
        this.#chartPointerLeft();
        return;
      }
      const x = chart.convertFromPixel({ xAxisIndex: 0 }, event.offsetX);
      this.#chartPointerMoved(this.#nearestIndex(x));
    });
    zr.on("globalout", () => this.#chartPointerLeft());

    if (this.selectionValue) {
      chart.dispatchAction({
        type: "takeGlobalCursor",
        key: "brush",
        brushOption: { brushType: "lineX", brushMode: "single" },
      });
      chart.on("brushEnd", (params) => {
        const range = params?.areas?.[0]?.coordRange;
        this.#selectionChanged(range ? { min: range[0], max: range[1] } : null, points, distanceDivisor);
      });
      return;
    }

    if (window.matchMedia("(pointer: fine)").matches) {
      chart.dispatchAction({ type: "takeGlobalCursor", key: "dataZoomSelect", dataZoomSelectActive: true });
    }
    chart.on("datazoom", () => {
      if (this.zoomRedraw) cancelAnimationFrame(this.zoomRedraw);
      this.zoomRedraw = requestAnimationFrame(() => {
        this.zoomRedraw = null;
        if (!this.chart || this.chart.isDisposed()) return;
        this.#zoomChanged();
        this.#afterLayout();
      });
    });
  }

  #chartPointerLeft() {
    if (this.hoverDistance === null) return;

    this.#setHover(null);
    this.#publishHover(null);
  }

  // The index of the plotted point nearest an x value; x grows along the
  // series (cumulative distance or elapsed time).
  #nearestIndex(x) {
    const xs = this.xValues;
    if (!xs?.length || !Number.isFinite(x)) return null;

    let low = 0;
    let high = xs.length - 1;
    while (high - low > 1) {
      const middle = (low + high) >> 1;
      if (xs[middle] <= x) low = middle; else high = middle;
    }
    return Math.abs(xs[high] - x) < Math.abs(x - xs[low]) ? high : low;
  }

  // What is drawn from pixel positions follows every layout change: the
  // first render, a resize, a zoom.
  #afterLayout() {
    this.#drawAxisLabels();
    this.#redrawCursor();
  }

  // The plot rectangle in the chart's own pixels and the x range it shows,
  // from the grid insets and the public pixel conversion.
  #plotGeometry() {
    const chart = this.chart;
    if (!chart || chart.isDisposed()) return null;

    const width = chart.getWidth();
    const height = chart.getHeight();
    const left = GRID_SIDE;
    const right = width - GRID_SIDE;
    const top = GRID_TOP;
    const bottom = height - (this.gridBottom ?? 0);
    if (!(right > left) || !(bottom > top)) return null;

    const minX = chart.convertFromPixel({ xAxisIndex: 0 }, left);
    const maxX = chart.convertFromPixel({ xAxisIndex: 0 }, right);
    if (!Number.isFinite(minX) || !Number.isFinite(maxX) || !(maxX > minX)) return null;

    return { left, top, width: right - left, height: bottom - top, minX, maxX };
  }

  // Tagged with its origin so the two controllers cannot echo each other.
  #publishHover(index) {
    const point = Number.isInteger(index) && index >= 0 ? this.points?.[index] : null;
    const detail = point && Number.isFinite(point.distance)
      ? { source: "chart", distance: point.distance }
      : { source: "chart", clear: true };

    window.dispatchEvent(new CustomEvent(TRACK_HOVER, { detail }));
  }

  #selectionChanged(xaxis, points, distanceDivisor) {
    const minimum = Number(xaxis?.min);
    const maximum = Number(xaxis?.max);
    if (!Number.isFinite(minimum) || !Number.isFinite(maximum) || minimum === maximum) {
      window.dispatchEvent(new CustomEvent("allure:segment-selection", { detail: { clear: true } }));
      return;
    }

    const lower = Math.min(minimum, maximum) * distanceDivisor;
    const upper = Math.max(minimum, maximum) * distanceDivisor;
    const selected = points.filter((point) => point.distance >= lower && point.distance <= upper);
    if (selected.length < 2 || selected[0].index === undefined || selected.at(-1).index === undefined) {
      window.dispatchEvent(new CustomEvent("allure:segment-selection", { detail: { clear: true } }));
      return;
    }

    window.dispatchEvent(new CustomEvent("allure:segment-selection", {
      detail: {
        startIndex: selected[0].index,
        endIndex: selected.at(-1).index,
        startSegmentIndex: selected[0].segment_index,
        endSegmentIndex: selected.at(-1).segment_index,
      },
    }));
  }

  #foregroundColor() {
    return cssColor("--body-color", "#374151");
  }

  // The primary series is the product primary now that sport no longer owns a
  // colour (DESIGN.md §6/§15.1).
  #primaryColor() {
    return cssColor("--primary", "#c5426c");
  }

  #selectedSecondaryMetric() {
    return this.hasSecondaryMetricTarget ? this.secondaryMetricTarget.value : "";
  }

  // The secondary-series choice is remembered per kind of chart: a power-led
  // virtual ride keeps its own default instead of inheriting the speed an
  // outdoor ride was left on, and the reverse.
  #secondaryMetricStorageKey() {
    return this.powerLedValue ? "allure:workout-chart-secondary:power-led" : "allure:workout-chart-secondary";
  }

  #restoreSecondaryMetric() {
    if (!this.hasSecondaryMetricTarget) return;

    try {
      const saved = localStorage.getItem(this.#secondaryMetricStorageKey());
      if ([...this.secondaryMetricTarget.options].some((option) => option.value === saved)) {
        this.secondaryMetricTarget.value = saved;
      }
    } catch {
      // Storage can be disabled without disabling the chart.
    }
  }

  #storeSecondaryMetric() {
    if (!this.hasSecondaryMetricTarget) return;

    try {
      localStorage.setItem(this.#secondaryMetricStorageKey(), this.secondaryMetricTarget.value);
    } catch {
      // Storage can be disabled without disabling the chart.
    }
  }

  #rawSecondaryValue(point, metric) {
    const key = metric === "pace" ? "speed" : metric;
    return this.#numericValue(point[key]);
  }

  #numericValue(value) {
    return Number.isFinite(value) ? value : null;
  }

  #secondaryDescriptor(metric, imperial) {
    const speedMultiplier = imperial ? 2.2369362921 : 3.6;
    const speedUnit = imperial ? this.milesPerHourLabelValue : this.kilometresPerHourLabelValue;
    // A sport with its own pace basis (rowing's /500 m) overrides the viewer
    // kilometre or mile: the split is the sport's convention, not a unit.
    const basis = this.hasPaceBasisValue ? Number(this.paceBasisValue) : null;
    const paceDistance = basis || (imperial ? METRES_PER_MILE : METRES_PER_KILOMETRE);
    const paceUnit = basis
      ? this.paceBasisLabelValue
      : (imperial ? `/${this.mileLabelValue}` : `/${this.kilometreLabelValue}`);

    switch (metric) {
      case "speed": {
        const fromRaw = (speed) => (speed === null ? null : speed * speedMultiplier);
        return {
          label: this.speedLabelValue,
          axisTitle: `${this.speedLabelValue} (${speedUnit})`,
          unit: speedUnit,
          raw: (point) => this.#numericValue(point.speed),
          fromRaw,
          value: (point) => fromRaw(this.#numericValue(point.speed)),
          axisFormatter: (value) => formatNumber(Number(value), 1),
          tooltipFormatter: (value) => value === null ? "—" : `${formatNumber(Number(value), 1)} ${speedUnit}`,
        };
      }
      case "pace": {
        const toPace = (speed) => (speed > 0 ? paceDistance / speed : null);
        const fromRaw = (speed) => (speed === null ? null : toPace(speed));
        return {
          label: this.paceLabelValue,
          axisTitle: `${this.paceLabelValue} (${paceUnit})`,
          unit: paceUnit,
          raw: (point) => this.#numericValue(point.speed),
          fromRaw,
          value: (point) => fromRaw(this.#numericValue(point.speed)),
          axisFormatter: (reading) => this.#formatPace(reading),
          tooltipFormatter: (reading) => reading === null ? "—" : `${this.#formatPace(reading)} ${paceUnit}`,
        };
      }
      case "heart_rate":
        return this.#integerDescriptor(metric, this.heartRateLabelValue, this.heartRateUnitValue);
      case "cadence":
        return this.#integerDescriptor(metric, this.cadenceLabelValue, this.cadenceUnitValue);
      case "power":
        return this.#integerDescriptor(metric, this.powerLabelValue, this.powerUnitValue);
      // The weather model's air temperature, or the device's own reading.
      case "temperature":
      case "device_temperature": {
        const unit = imperial ? this.fahrenheitUnitValue : this.celsiusUnitValue;
        const label = metric === "temperature" ? this.temperatureLabelValue : this.deviceTemperatureLabelValue;
        const fromRaw = (celsius) => (celsius === null ? null : (imperial ? celsius * 9 / 5 + 32 : celsius));
        return {
          label,
          axisTitle: `${label} (${unit})`,
          unit,
          raw: (point) => this.#numericValue(point[metric]),
          fromRaw,
          value: (point) => fromRaw(this.#numericValue(point[metric])),
          axisFormatter: (value) => formatNumber(Math.round(Number(value))),
          tooltipFormatter: (value) => value === null ? "—" : `${formatNumber(Math.round(Number(value)))} ${unit}`,
        };
      }
      // Positive against the direction of travel, negative behind.
      case "headwind": {
        const fromRaw = (speed) => (speed === null ? null : speed * speedMultiplier);
        return {
          label: this.headwindLabelValue,
          axisTitle: `${this.headwindLabelValue} (${speedUnit})`,
          unit: speedUnit,
          raw: (point) => this.#numericValue(point.headwind),
          fromRaw,
          value: (point) => fromRaw(this.#numericValue(point.headwind)),
          axisFormatter: (value) => formatNumber(Math.round(Number(value))),
          tooltipFormatter: (value) => value === null ? "—" : `${formatNumber(Math.round(Number(value)))} ${speedUnit}`,
        };
      }
      default:
        return null;
    }
  }

  #integerDescriptor(key, label, unit) {
    const raw = (point) => this.#numericValue(point[key]);
    return {
      label,
      axisTitle: unit ? `${label} (${unit})` : label,
      unit: unit || "",
      raw,
      fromRaw: (value) => value,
      value: raw,
      axisFormatter: (value) => formatNumber(value),
      tooltipFormatter: (value) => value === null ? "—" : `${formatNumber(value)}${unit ? ` ${unit}` : ""}`,
    };
  }

  // The plotted secondary line is display-smoothed over a window that follows
  // the plotted span (about 1 % of it, never under the map's medium window,
  // wider on phones); the tooltip still reads the recorded sample through
  // `secondary.value`, so the line and the data table cannot disagree on a
  // value (DESIGN.md §15.1).
  #secondarySeriesData(points, secondary, distanceDivisor, spanMetres, xOf = (point) => point.distance / distanceDivisor) {
    const distances = points.map((point) => point.distance);
    // Sparse sensors leave one- or two-sample holes; short ones are bridged
    // for the drawing only (never across a recording gap), long ones stay.
    const raw = bridgeShortGaps(points.map((point) => secondary.raw(point)), distances, {
      maxGapMetres: Math.max(100, (spanMetres || 0) * 0.02),
      segments: recordingRuns(points),
    });
    const smoothed = smoothSeriesValues(raw, distances, {
      halfWindowMetres: chartHalfWindowMetres(spanMetres, { compact: Boolean(this.mobileMedia?.matches) }),
    });
    return points.map((point, position) => ({
      x: xOf(point),
      y: secondary.fromRaw(smoothed[position]),
      elapsedTime: point.elapsed_time,
      index: point.index,
      segmentIndex: point.segment_index,
    }));
  }

  // An upper bound: niceScale picks the round step, then the real count.
  #yAxisTickAmount() {
    return this.mobileMedia?.matches ? 4 : 5;
  }

  // The profile zooms by selecting a range: a mouse drag (the toolbox's
  // select-zoom) or, on touch screens, a press held still and then dragged.
  // The reset button brings back the fitted view.
  zoomReset() {
    if (!this.chart || this.chart.isDisposed()) return;

    this.chart.dispatchAction({ type: "dataZoom", start: 0, end: 100 });
    this.#setZoomed(false);
  }

  // Whole-distance ticks (0, 10, 20 km — never tenths) placed on the plot's
  // own scale, so they stay true when zoomed and after every redraw, plus
  // the top value of each y axis inside the plot's top corners.
  #drawAxisLabels() {
    if (!this.hasXTicksTarget) return;

    const target = this.xTicksTarget;
    const geometry = this.#plotGeometry();
    if (!geometry) {
      target.replaceChildren();
      return;
    }

    const origin = target.parentElement.getBoundingClientRect();
    const box = this.chartTarget.getBoundingClientRect();
    const left = box.left - origin.left + geometry.left;
    const top = box.top - origin.top + geometry.top + geometry.height + 6;
    const span = geometry.maxX - geometry.minX;
    const step = Math.max(1, Math.round(niceScale(0, span, this.mobileMedia?.matches ? 4 : 6).step));
    const ticks = [];
    for (let value = Math.ceil(geometry.minX / step) * step; value <= geometry.maxX + 1e-9; value += step) {
      const tick = document.createElement("span");
      tick.className = "allure-chart-xtick";
      // The time axis counts minutes; its ticks read as durations.
      tick.textContent = this.timeAxis ? this.#formatDuration(Math.round(value * 60)) : formatNumber(value);
      const offset = ((value - geometry.minX) / span) * geometry.width;
      tick.style.left = `${left + offset}px`;
      // The labels at the plot's edges stay inside the card.
      if (offset < 8) tick.style.transform = "none";
      else if (geometry.width - offset < 8) tick.style.transform = "translateX(-100%)";
      tick.style.top = `${top}px`;
      ticks.push(tick);
    }
    const plotTop = box.top - origin.top + geometry.top + 2;
    for (const { side, text } of this.axisLabels ?? []) {
      const label = document.createElement("span");
      label.className = `allure-chart-ylabel allure-chart-ylabel--${side}`;
      label.textContent = text;
      label.style.top = `${plotTop}px`;
      label.style.left = `${side === "end" ? left + geometry.width - 4 : left + 4}px`;
      ticks.push(label);
    }
    target.replaceChildren(...ticks);
    this.#drawAnomalies();
    this.#drawPhotos();
  }

  // The photo gallery republishes its placed photos after every change.
  photosChanged(event) {
    const markers = event.detail?.markers;
    if (!Array.isArray(markers)) return;
    this.photosValue = markers;
    this.#drawPhotos();
  }

  // One camera pill per placed photo along the top of the plot, on the
  // plot's own scale so it stays true when zoomed. Opening one shows the
  // photo in the gallery's lightbox.
  #drawPhotos() {
    if (!this.hasPhotosTarget) return;

    const target = this.photosTarget;
    const geometry = this.#plotGeometry();
    if (!geometry || !this.distanceDivisor || this.timeAxis) {
      target.replaceChildren();
      return;
    }

    const origin = target.parentElement.getBoundingClientRect();
    const box = this.chartTarget.getBoundingClientRect();
    const left = box.left - origin.left + geometry.left;
    const top = box.top - origin.top + geometry.top + 18;
    const { minX, maxX, width: plotWidth } = geometry;
    const marks = [];

    for (const photo of this.photosValue) {
      const value = Number(photo?.distance) / this.distanceDivisor;
      if (!Number.isFinite(value) || value < minX || value > maxX || typeof photo.id !== "string") continue;

      const mark = document.createElement("button");
      mark.type = "button";
      mark.className = "allure-chart-photo";
      mark.style.left = `${left + ((value - minX) / (maxX - minX)) * plotWidth}px`;
      mark.style.top = `${top}px`;
      mark.setAttribute("aria-label", typeof photo.label === "string" ? photo.label : "");
      const icon = document.createElement("i");
      icon.className = "ti ti-camera";
      icon.setAttribute("aria-hidden", "true");
      mark.append(icon);
      mark.addEventListener("click", () => {
        window.dispatchEvent(new CustomEvent("allure:photo-open", { detail: { id: photo.id } }));
      });
      marks.push(mark);
    }
    target.replaceChildren(...marks);
  }

  // On the plot's own scale, like the distance ticks, so the dashes stay
  // true when zoomed. Hovering one previews its range on the chart and the
  // map through the analysis card, exactly like a row of its tab, and names
  // the finding through the shared Bootstrap tooltip.
  #drawAnomalies() {
    this.#disposeAnomalyTooltips();
    if (!this.hasAnomaliesTarget) return;

    const target = this.anomaliesTarget;
    const geometry = this.#plotGeometry();
    if (!geometry || !this.distanceDivisor) {
      target.replaceChildren();
      return;
    }

    const origin = target.parentElement.getBoundingClientRect();
    const box = this.chartTarget.getBoundingClientRect();
    const left = box.left - origin.left + geometry.left;
    const foot = box.top - origin.top + geometry.top + geometry.height - ANOMALY_FOOT_INSET;
    const { minX, maxX, width: plotWidth } = geometry;
    const span = maxX - minX;
    const shown = this.anomaliesValue.filter((anomaly) => this.inspectAnomalies || anomaly?.tier === "major");
    const rows = [...new Set(shown
      .map((anomaly) => ANOMALY_ROWS[anomaly?.family])
      .filter((row) => row !== undefined))].sort();
    const marks = [];

    for (const anomaly of shown) {
      const row = rows.indexOf(ANOMALY_ROWS[anomaly?.family]);
      const start = Number(anomaly?.start) / this.distanceDivisor;
      const end = Number(anomaly?.end) / this.distanceDivisor;
      if (row === -1 || !Number.isFinite(start) || !Number.isFinite(end)) continue;
      if (end < minX || start > maxX) continue;

      let from = ((Math.max(start, minX) - minX) / span) * plotWidth;
      let to = ((Math.min(end, maxX) - minX) / span) * plotWidth;
      if (to - from < ANOMALY_MIN_WIDTH) {
        const middle = (from + to) / 2;
        from = Math.max(0, middle - ANOMALY_MIN_WIDTH / 2);
        to = Math.min(plotWidth, from + ANOMALY_MIN_WIDTH);
      }

      const mark = document.createElement("span");
      mark.className = `allure-chart-anomaly allure-chart-anomaly--${anomaly.family}`;
      mark.style.left = `${left + from}px`;
      mark.style.width = `${to - from}px`;
      mark.style.top = `${foot - row * ANOMALY_ROW_SPACING}px`;
      if (typeof anomaly.label === "string") mark.dataset.anomalyLabel = anomaly.label;
      const step = { distance: Number(anomaly.start), endDistance: Number(anomaly.end), source: "anomaly" };
      if (step.endDistance - step.distance < 40) {
        const middle = (step.distance + step.endDistance) / 2;
        step.distance = Math.max(0, middle - 20);
        step.endDistance = step.distance + 40;
      }
      mark.addEventListener("mouseenter", () => {
        this.stepPreview(step);
        this.#showAnomalyTooltip(mark);
      });
      mark.addEventListener("mouseleave", () => {
        this.stepPreview(null);
        this.#hideAnomalyTooltip(mark);
      });
      marks.push(mark);
    }
    target.replaceChildren(...marks);
  }

  // The dash's finding through the shared Bootstrap tooltip the page uses for
  // every tooltip, never a native `title` (DESIGN.md §15.5). Created on first
  // hover and reused, like the calendar's cells: an inspected recording can
  // hold many dashes, and the marks are rebuilt on every zoom or theme change.
  #showAnomalyTooltip(mark) {
    const label = mark.dataset.anomalyLabel;
    if (!label || !window.bootstrap?.Tooltip) return;

    let tooltip = this.anomalyTooltips.get(mark);
    if (!tooltip) {
      tooltip = new window.bootstrap.Tooltip(mark, {
        trigger: "manual",
        container: "body",
        title: label,
      });
      this.anomalyTooltips.set(mark, tooltip);
    }
    tooltip.show();
  }

  #hideAnomalyTooltip(mark) {
    this.anomalyTooltips.get(mark)?.hide();
  }

  #disposeAnomalyTooltips() {
    for (const tooltip of this.anomalyTooltips?.values() ?? []) tooltip.dispose();
    this.anomalyTooltips?.clear();
  }

  // Zoomed while the plot shows less than the whole activity.
  #zoomChanged() {
    const geometry = this.#plotGeometry();
    const total = this.xValues?.at(-1);
    if (!geometry || !Number.isFinite(total)) return this.#setZoomed(false);

    const tolerance = (geometry.maxX - geometry.minX) * 1e-3;
    this.#setZoomed(geometry.minX > tolerance || geometry.maxX < total - tolerance);
  }

  // The markers ride on the series, so they follow a zoom by themselves.
  #setZoomed(zoomed) {
    this.zoomed = zoomed;
    if (this.hasZoomResetTarget) this.zoomResetTarget.hidden = !zoomed;
  }

  #bindTouchSelection() {
    this.#releaseTouchSelection();
    if (this.selectionValue || !window.matchMedia("(pointer: coarse)").matches) return;

    const surface = this.chartTarget;
    let timer = null;
    let start = null;
    let selecting = false;

    const plot = () => {
      const geometry = this.#plotGeometry();
      if (!geometry) return null;
      const box = surface.getBoundingClientRect();
      return {
        left: box.left + geometry.left,
        width: geometry.width,
        minX: geometry.minX,
        maxX: geometry.maxX,
        top: box.top + geometry.top,
        height: geometry.height,
      };
    };
    const xAt = (clientX, area) => {
      const ratio = Math.min(Math.max((clientX - area.left) / area.width, 0), 1);
      return area.minX + ratio * (area.maxX - area.minX);
    };
    const drawBand = (fromX, toX, area) => {
      if (!this.hasTouchSelectionTarget) return;
      const box = surface.getBoundingClientRect();
      const left = Math.min(fromX, toX);
      const right = Math.max(fromX, toX);
      Object.assign(this.touchSelectionTarget.style, {
        left: `${Math.max(left, area.left) - box.left}px`,
        width: `${Math.min(right, area.left + area.width) - Math.max(left, area.left)}px`,
        top: `${area.top - box.top}px`,
        height: `${area.height}px`,
      });
      this.touchSelectionTarget.hidden = false;
    };
    const cancel = () => {
      clearTimeout(timer);
      timer = null;
      selecting = false;
      start = null;
      if (this.hasTouchSelectionTarget) this.touchSelectionTarget.hidden = true;
    };

    const onStart = (event) => {
      if (event.touches.length !== 1) return cancel();
      const touch = event.touches[0];
      start = { x: touch.clientX, y: touch.clientY };
      timer = setTimeout(() => {
        const area = plot();
        if (!area || !start) return;
        selecting = true;
        drawBand(start.x, start.x, area);
        navigator.vibrate?.(10);
      }, TOUCH_SELECT_DELAY);
    };
    const onMove = (event) => {
      if (!start) return;
      const touch = event.touches[0];
      if (!selecting) {
        // Moving before the delay is a scroll or a scrub: leave it alone.
        if (Math.hypot(touch.clientX - start.x, touch.clientY - start.y) > TOUCH_SELECT_SLOP) cancel();
        return;
      }
      event.preventDefault();
      const area = plot();
      if (area) drawBand(start.x, touch.clientX, area);
      start.lastX = touch.clientX;
    };
    const onEnd = () => {
      if (selecting && start && Number.isFinite(start.lastX)) {
        const area = plot();
        if (area) {
          const from = xAt(Math.min(start.x, start.lastX), area);
          const to = xAt(Math.max(start.x, start.lastX), area);
          if (to - from > (area.maxX - area.minX) * 0.02) {
            this.chart.dispatchAction({ type: "dataZoom", dataZoomId: "zoom", startValue: from, endValue: to });
          }
        }
      }
      cancel();
    };

    surface.addEventListener("touchstart", onStart, { passive: true });
    surface.addEventListener("touchmove", onMove, { passive: false });
    surface.addEventListener("touchend", onEnd);
    surface.addEventListener("touchcancel", cancel);
    this.touchSelectionCleanup = () => {
      cancel();
      surface.removeEventListener("touchstart", onStart);
      surface.removeEventListener("touchmove", onMove);
      surface.removeEventListener("touchend", onEnd);
      surface.removeEventListener("touchcancel", cancel);
    };
  }

  #releaseTouchSelection() {
    this.touchSelectionCleanup?.();
    this.touchSelectionCleanup = null;
  }

  // Every marker sits on the drawn curve. A mark point anchors on a data
  // coordinate, so the anchor is the series' value at the marker distance:
  // interpolated from the plotted line, then the toponymy sample, then the
  // middle of the axis.
  #anchorY(marker, fallbackElevation = null) {
    const value = this.#curveYAt(Number(marker.distance));
    if (value !== null) return value;
    if (fallbackElevation !== null && Number.isFinite(fallbackElevation)) {
      return fallbackElevation / this.elevationDivisor;
    }
    if (this.axisMin !== null && this.axisMax !== null) return (this.axisMin + this.axisMax) / 2;
    return 0;
  }

  // Linear interpolation on the anchor series. A marker inside a recording
  // gap still resolves to the chord between the surrounding recorded values.
  #curveYAt(distance) {
    const series = this.anchorSeries;
    if (!series?.length || !Number.isFinite(distance)) return null;

    const x = distance / this.distanceDivisor;
    let low = 0;
    let high = series.length - 1;
    if (x <= series[0].x) return this.#nearestSeriesY(series, 0);
    if (x >= series[high].x) return this.#nearestSeriesY(series, high);
    while (high - low > 1) {
      const middle = (low + high) >> 1;
      if (series[middle].x <= x) low = middle; else high = middle;
    }

    const before = this.#nearestSeriesY(series, low, -1);
    const after = this.#nearestSeriesY(series, high, 1);
    if (before === null) return after;
    if (after === null) return before;
    const span = series[high].x - series[low].x;
    const ratio = span > 0 ? (x - series[low].x) / span : 0;
    return before + (after - before) * ratio;
  }

  // Nearest non-null y from a position, scanning `direction` first.
  #nearestSeriesY(series, position, direction = 1) {
    for (let index = position; index >= 0 && index < series.length; index += direction) {
      if (series[index].y !== null) return series[index].y;
    }
    for (let index = position; index >= 0 && index < series.length; index -= direction) {
      if (series[index].y !== null) return series[index].y;
    }
    return null;
  }

  // Place numbers stay strictly on the curve. Only analysis pictograms move
  // when they crowd: a pictogram closer than 4% of the route to any previous
  // marker alternates above and below the curve, so a cluster of climbs or
  // stops never piles up (DESIGN.md §15.1). The offsets are pixel offsets of
  // the drawn symbol, so the anchor never leaves the curve.
  #iconOffsets() {
    const entries = [
      ...(this.markers ?? []).map((marker) => ({ marker, distance: marker.distance, icon: false })),
      ...(this.analysisMarkers ?? []).map((marker) => ({ marker, distance: Number(marker.distance), icon: true })),
    ].sort((a, b) => a.distance - b.distance);

    const offsets = new Map();
    let previous = null;
    let below = null;
    for (const entry of entries) {
      if (entry.icon) {
        if (previous !== null && entry.distance - previous < this.markerGap) {
          if (below === null) below = this.#nearAxisTop(entry.marker);
          offsets.set(entry.marker, below ? ICON_OFFSET : -ICON_OFFSET);
          below = !below;
        } else {
          offsets.set(entry.marker, 0);
        }
      }
      previous = entry.distance;
    }
    return offsets;
  }

  // A pictogram anchored in the top quarter of the axis starts below the
  // curve, so the first offset never pushes it out of the plot.
  #nearAxisTop(marker) {
    if (this.axisMin === null || this.axisMax === null || this.axisMax <= this.axisMin) return false;

    const y = this.#anchorY(marker);
    const position = (y - this.axisMin) / (this.axisMax - this.axisMin);
    const visualPosition = this.anchorReversed ? 1 - position : position;
    return visualPosition > 0.75;
  }

  #formatPace(seconds) {
    if (!Number.isFinite(seconds)) return "—";

    const rounded = Math.round(seconds);
    return `${Math.floor(rounded / 60)}:${String(rounded % 60).padStart(2, "0")}`;
  }

  #formatDuration(seconds) {
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const remainder = seconds % 60;
    return hours > 0
      ? `${hours}:${String(minutes).padStart(2, "0")}:${String(remainder).padStart(2, "0")}`
      : `${minutes}:${String(remainder).padStart(2, "0")}`;
  }

  // The time axis unit. It is always minutes; the label is the same word the
  // tooltip's elapsed row uses, so the two cannot drift apart.
  #minuteLabel() {
    return this.minuteLabelValue || this.elapsedTimeLabelValue;
  }

  #showState(state) {
    if (this.hasLoadingTarget) this.loadingTarget.hidden = state !== "loading";
    if (this.hasErrorTarget) this.errorTarget.hidden = state !== "error";
    if (this.hasEmptyTarget) this.emptyTarget.hidden = state !== "empty";
    if (this.hasChartTarget) this.chartTarget.hidden = state === "error" || state === "empty";
    if (this.hasPlacesTarget && state !== "ready") this.placesTarget.hidden = true;
  }
}
