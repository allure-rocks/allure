import { Controller } from "@hotwired/stimulus";
import { cssColor } from "../lib/css_color";
import {
  DIRECTION_IMAGE_ID,
  DIRECTION_LAYER_ID,
  directionFeatureCollection,
  directionLayer,
  ensureDirectionImage,
  geographicChevronFeatures,
} from "../lib/direction_chevrons";
import { overlayAnchorLayerId } from "../lib/map_overlay_anchor";
import { WORLD_BACKGROUND_LAYER_ID, WORLD_LAYER_ID, worldBackground, worldPaint, worldStyle } from "../lib/virtual_world";
import { collapseAttribution } from "../lib/map_attribution";
import { applyBasemapTheme, basemapFollowsPage, documentTheme, resolveBasemapTheme } from "../lib/basemap_theme";
import { smoothCoordinates, validSmoothingLevel } from "../lib/track_smoothing";
import { ANOMALY_INSPECT_EVENT, anomalyInspecting } from "../lib/anomaly_inspect";
import { weatherIconUrl } from "../lib/weather_icons";
import { robustExtent } from "../lib/chart_scale";

// [longitude, latitude] throughout. That is GeoJSON order and also MapLibre's
// own order, so unlike the Leaflet implementation this replaced there is no
// axis conversion anywhere in this file.
const DEFAULT_CENTER = [2.5, 46.6];
const DEFAULT_ZOOM = 4.5;
const FIT_PADDING = 24;
// Photo thumbnails closer than one marker on screen share a marker.
const PHOTO_CLUSTER_PIXELS = 40;

const TRACK_SOURCE = "allure-track";
const TRACK_LAYER_PREFIX = "allure-track-line";
const TRACK_HIT_LAYER = "allure-track-hit";
const SELECTION_SOURCE = "allure-selection";
const SELECTION_LAYER = "allure-selection-line";
const DIRECTION_SOURCE = "allure-direction";
const ANOMALY_SOURCE = "allure-anomalies";
const ANOMALY_LAYER = "allure-anomaly-dashes";
const ANOMALY_POINT_LAYER = "allure-anomaly-points";

// A virtual world's own map image (PLAN_VIRTUAL.md) replaces the ordinary
// basemap: one background layer in the world's colour and one image layer
// stretched over the world's rectangle. No tiles are fetched.

// Flagged readings (owner-only) are drawn as short dashes over the track. A
// finding at one point still gets a visible slice this long around it.
const ANOMALY_MIN_RANGE_METRES = 40;

const EMPTY_COLLECTION = { type: "FeatureCollection", features: [] };

// Metrics a track can be coloured by, in the order they are offered. The
// default is a flat brand line; a chosen metric shades it light to dark.
const FLAT_METRIC = "flat";
const METRICS = ["elevation", "speed", "power"];

// A reading that spikes — a GPS jump, a stop, a sprint — would otherwise
// decide the whole ramp, so these span the bulk of their values (the chart's
// own 2nd–98th percentile). Elevation keeps its true extremes.
const ROBUST_METRICS = new Set(["speed", "power"]);

// A 1 Hz power or speed reading is noisy enough that one point per colour stop
// paints static; each stop takes the mean of its own slice of the route
// instead. Elevation is sampled, which preserves its summits.
const BINNED_METRICS = new Set(["speed", "power"]);

// One colour stop per point would produce an expression with tens of thousands
// of entries for a long ride. Sampling to this many is visually indistinguishable
// and keeps the style document small.
const GRADIENT_STOPS = 96;

// Hover position is exchanged with the elevation chart as a distance along the
// workout, in metres. See the matching constant in the chart controller.
const TRACK_HOVER = "allure:track-hover";

// The route cursor is revealed from this many screen pixels around the line,
// so hitting a 4px track does not demand pixel precision. While the pointer is
// inside that band it is hidden: the ball is the cursor.
const TRACK_HOVER_HIT_WIDTH = 24;

// Used when the configured basemap cannot be fetched. MapLibre needs a valid
// style to render at all, and this one renders nothing, which leaves the themed
// grid background of .allure-map showing behind the route.
const BLANK_STYLE = { version: 8, sources: {}, layers: [] };

export default class extends Controller {
  static targets = [
    "canvas", "loading", "error", "empty", "metric", "smoothing", "placing", "placingText",
    "legend", "legendTitle", "legendRamp", "legendLow", "legendHigh",
  ];

  static values = {
    center: { type: Array, default: DEFAULT_CENTER },
    zoom: { type: Number, default: DEFAULT_ZOOM },
    url: String,
    // Sanitized track handed inline by the publication preview. When present it
    // replaces the endpoint fetch: a candidate publication does not exist yet
    // and has no track URL.
    geojson: Object,
    styleUrl: String,
    styleUrlDark: String,
    // The candidate preview embeds the map as a thumbnail: no zoom, fullscreen
    // or scale controls. Attribution is always kept — the tile licence requires
    // it, and it is not optional chrome.
    controls: { type: Boolean, default: true },
    unitSystem: { type: String, default: "metric" },
    locale: Object,
    // The colour-by legend's metric names and units (DESIGN.md §15.2).
    legendLocale: Object,
    // A power-led virtual ride offers its watts first and keeps its own stored
    // colour choice (PLAN_VIRTUAL.md §8).
    powerLed: { type: Boolean, default: false },
    startLabel: String,
    finishLabel: String,
    // Display-only track smoothing. `smoothing` is the effective level for
    // this map ("off" by default); `smoothingLevel` is the account's chosen
    // intensity, restored when the options toggle is switched back on.
    smoothing: { type: String, default: "off" },
    smoothingLevel: { type: String, default: "medium" },
    smoothingControl: { type: Boolean, default: false },
    smoothingPersistUrl: String,
    // Owner-only position and timing findings (DESIGN.md §15.5): distance
    // ranges along the track, plus the coordinates of rejected positions.
    anomalies: { type: Array, default: [] },
    // The owner's placed photos (PLAN_PHOTOS.md §7): id, lon, lat, thumbnail
    // endpoint and label. Thumbnails sharing a spot at the current zoom are
    // grouped under one marker with a count.
    photos: { type: Array, default: [] },
    // The account's basemap preference (`auto`, `light`, `dark`; DESIGN.md
    // §15.2). The server already paints the resolved theme on the canvas.
    basemapTheme: { type: String, default: "auto" },
    // A virtual world's map image: `image`, its four `coordinates`, the
    // `background` colour around it and the `attribution` credit. Present
    // instead of a style URL, never beside one.
    virtualBasemap: Object,
  };

  async connect() {
    this.connected = true;
    applyBasemapTheme(this.mapElement, this.#basemapTheme());
    this.selection = null;
    this.highlightRange = null;
    this.highlightSource = null;
    this.stopMarkerData = [];
    this.stopMarkers = [];
    this.weatherMarkerData = [];
    this.weatherMarkers = [];
    this.photoMarkers = [];
    this.placingPhoto = null;
    this.markers = [];
    this.segments = null;
    this.trackLayerIds = [];
    // The metric ranges are normalised across the whole workout and recomputed
    // only when the segments change.
    this.metricRanges = {};
    this.metric = FLAT_METRIC;
    this.#restoreMetric();
    // The effective display smoothing; segments keep it at "medium", workout
    // maps follow the account preference and the options toggle below.
    this.activeSmoothing = validSmoothingLevel(this.smoothingValue) ? this.smoothingValue : "off";
    this.abortController = new AbortController();
    // Only the findings that change a figure show until the owner inspects
    // every one from the data quality tab.
    this.inspectAnomalies = anomalyInspecting();
    this.anomalyInspectChanged = (event) => {
      this.inspectAnomalies = Boolean(event.detail?.inspect);
      this.map?.getSource(ANOMALY_SOURCE)?.setData(this.#anomalyCollection());
    };
    window.addEventListener(ANOMALY_INSPECT_EVENT, this.anomalyInspectChanged);
    this.#showState("loading");

    // MapLibre is around 250 kB gzipped, and this application registers every
    // Stimulus controller eagerly. Importing it statically would charge that to
    // the timeline, the dashboard and every other page that has no map.
    //
    // The worker URL has to be handed over explicitly. MapLibre 6 loads its
    // worker from a real URL derived from a runtime-built template, which no
    // bundler can resolve statically, so every bundler needs a one-time
    // setWorkerUrl call. The `?worker&url` query is Vite's: plain `?url` would
    // emit the worker verbatim without the sibling module it imports, and no
    // tile — basemap or track — would ever render.
    const [maplibre, { default: workerUrl }] = await Promise.all([
      import("maplibre-gl"),
      import("maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url"),
    ]);
    if (!this.connected) return;
    maplibre.setWorkerUrl(workerUrl);

    // The style is fetched here rather than handed to MapLibre as a URL so that
    // a failure is a value we can branch on. The basemap is a third-party
    // document with no availability guarantee, and losing it must not lose the
    // track. The trade-off is that a style using relative asset URLs would lose
    // its base; the configured basemaps use absolute ones.
    this.currentStyleUrl = this.hasVirtualBasemapValue ? null : this.#styleUrlForTheme(this.#basemapTheme());
    const [style, features] = await Promise.all([
      this.hasVirtualBasemapValue
        ? Promise.resolve(this.#worldStyle(this.#basemapTheme()))
        : this.#loadStyle(this.currentStyleUrl),
      this.#loadTrack(),
    ]);
    if (!this.connected) return;

    if (features === null) {
      this.#showState("error");
      return;
    }

    this.maplibre = maplibre;
    this.map = new maplibre.Map({
      container: this.mapElement,
      style,
      center: this.centerValue,
      zoom: this.zoomValue,
      scrollZoom: false,
      // On touch screens one finger scrolls the page and two move the map, so
      // a map that fills the phone viewport never traps the reader. The
      // fullscreen control lifts it while the map fills the screen.
      cooperativeGestures: window.matchMedia("(pointer: coarse)").matches,
      locale: this.localeValue,
      attributionControl: false,
    });

    // Added images are part of the style, so a theme swap discards them. The
    // arrow halo is the themed surface, which is exactly why it is
    // re-registered from the live tokens rather than carried as a colour.
    this.map.on("style.load", () => this.#registerDirectionImage());
    this.map.on("styleimagemissing", (event) => {
      if (event?.id === DIRECTION_IMAGE_ID) this.#registerDirectionImage();
    });

    this.#addControls();

    // Chevron slots are a screen constant, so the geographic anchors are
    // recomputed only when the scale changes; pan, rotate and theme swaps keep
    // the map-aligned anchors valid.
    this.map.on("zoomend", () => {
      this.#refreshDirections();
      this.#renderPhotoMarkers();
    });
    this.map.on("rotate", () => this.#orientWeatherArrows());

    this.#whenStyleReady(() => {
      this.#draw(features);
      // The theme can be toggled while the style and track are still in flight,
      // in which case the basemap just loaded is already the wrong one.
      this.#applyTheme(this.#basemapTheme());
    });
  }

  disconnect() {
    this.connected = false;
    window.removeEventListener(ANOMALY_INSPECT_EVENT, this.anomalyInspectChanged);
    this.abortController?.abort();
    this.markers.forEach((marker) => marker.remove());
    this.stopMarkers?.forEach((marker) => marker.remove());
    this.weatherMarkers?.forEach((marker) => marker.remove());
    this.photoMarkers?.forEach((marker) => marker.remove());
    window.clearTimeout(this.photoPulseTimer);
    this.#stopPlacing();
    this.hoverMarker?.remove();
    this.map?.remove();
    this.photoMarkers = [];

    this.hoverMarker = null;
    this.markers = [];
    this.stopMarkers = [];
    this.stopMarkerData = [];
    this.weatherMarkers = [];
    this.weatherMarkerData = [];
    this.map = null;
    this.maplibre = null;
    this.abortController = null;
    this.selection = null;
    this.highlightRange = null;
    this.highlightSource = null;
    this.segments = null;
    this.trackLayerIds = [];
    this.activeSmoothing = "off";
    this.currentStyleUrl = null;
  }

  // The theme toggle publishes on window; the elevation chart listens to the
  // same event.
  // A forced basemap ignores it: nothing inside the map follows the page then.
  themeChanged(event) {
    if (!basemapFollowsPage(this.basemapThemeValue)) return;

    const theme = resolveBasemapTheme(this.basemapThemeValue, event.detail?.theme);
    applyBasemapTheme(this.mapElement, theme);
    // MapLibre's style diff may preserve runtime images. Repaint the halo
    // explicitly, including on tile-less maps whose style never changes.
    if (this.map?.hasImage(DIRECTION_IMAGE_ID)) {
      this.map.removeImage(DIRECTION_IMAGE_ID);
      this.#registerDirectionImage();
    }
    this.#applyTheme(theme);
  }

  // The chart publishes where the pointer is on the profile; mark the matching
  // place on the route. Silently does nothing when the workout has no chart.
  trackHover(event) {
    if (!this.map || event.detail?.source === "map") return;

    const distance = event.detail?.clear ? null : event.detail?.distance;
    const coordinates = Number.isFinite(distance) ? this.#coordinatesAtDistance(distance) : null;
    this.#moveHoverMarker(coordinates);
  }

  // The colour-by selector in the card header.
  metricChanged(event) {
    const metric = event.target.value;
    if (metric !== FLAT_METRIC && !METRICS.includes(metric)) return;
    if (metric === this.metric) return;

    this.metric = metric;
    this.#storeMetric();
    this.#paintTrack();
    this.#renderLegend();
  }

  // The options checkbox in the card header. Applies immediately and persists
  // the account preference; a failed round-trip only costs persistence, the
  // display has already changed.
  smoothingToggled(event) {
    this.activeSmoothing = event.target.checked ? this.#accountSmoothingLevel() : "off";
    this.#applySmoothing();
    this.#persistSmoothing(event.target.checked);
    // The workout page can carry a second map (the publication snapshot); keep
    // every map on the page in step without a reload.
    window.dispatchEvent(new CustomEvent("allure:smoothing-changed", {
      detail: { smoothing: this.activeSmoothing },
    }));
  }

  // A sibling map toggled the preference.
  smoothingChanged(event) {
    const smoothing = validSmoothingLevel(event.detail?.smoothing) ? event.detail.smoothing : "off";
    if (smoothing === this.activeSmoothing) return;

    this.activeSmoothing = smoothing;
    if (this.hasSmoothingTarget) this.smoothingTarget.checked = smoothing !== "off";
    this.#applySmoothing();
  }

  get mapElement() {
    return this.hasCanvasTarget ? this.canvasTarget : this.element;
  }

  // Called from the elevation chart through a window event while a segment is
  // being drawn. Tolerates arriving before the track has been drawn: the
  // selection is remembered and applied once the layers exist.
  highlightSelection(event) {
    this.selection = event.detail?.clear ? null : event.detail;
    if (!this.map?.getSource(SELECTION_SOURCE)) return;

    if (this.selection) this.#drawSelection(this.selection);
    else this.#clearSelection();
  }

  // Hovering, focusing, or pinning a lap row publishes its distance range. The
  // workout show page never drives a segment selection, so the two share the
  // one overlay without ever fighting. A range straddling a recording gap is
  // drawn as one line per segment, never across the gap. A stop additionally
  // enlarges its panel marker; a heart-rate zone carries every stretch where
  // it was ridden, drawn together.
  analysisHighlight(event) {
    const start = Number(event.detail?.startDistance);
    const end = Number(event.detail?.endDistance);
    const ranges = Array.isArray(event.detail?.ranges) ? event.detail.ranges : null;
    this.highlightRange = event.detail?.clear || !Number.isFinite(start) || !Number.isFinite(end) || end <= start
      ? null
      : { start, end, ranges };
    this.highlightSource = event.detail?.clear ? null : (event.detail?.source ?? null);

    if (this.map?.getSource(SELECTION_SOURCE)) {
      if (this.highlightRange) this.#drawHighlight(this.highlightRange);
      else this.#clearSelection();
    }
    this.#applyStopHighlight();
  }

  // The stops tab publishes its stop markers so the map shows a small stop
  // panel for every stop while that tab is active; the weather tab likewise
  // publishes its weather markers (PLAN_WEATHER.md §7).
  analysisTabChanged(event) {
    const markers = Array.isArray(event.detail?.markers) ? event.detail.markers : [];
    this.stopMarkerData = markers.filter((marker) => (
      marker?.glyph === "stop" && Number.isFinite(Number(marker.distance))
    ));
    this.weatherMarkerData = markers.filter((marker) => (
      marker?.kind === "weather" && Number.isFinite(Number(marker.distance))
    ));
    this.#renderStopMarkers();
    this.#renderWeatherMarkers();
  }

  // Deliberately not the "load" event. That one waits for every tile, sprite and
  // glyph the basemap references, and against a third-party basemap it can stay
  // pending indefinitely — observed against the default one, where the style
  // parses and renders but `loaded()` never becomes true. The route must not be
  // hostage to that. "style.load" fires as soon as the style document is
  // parsed, which is exactly when sources and layers become addable.
  #whenStyleReady(callback) {
    const run = () => {
      if (this.connected) callback();
    };

    // The style is handed over as an object, so it may already be parsed by the
    // time this runs and the event would never arrive.
    if (this.#styleParsed()) run();
    else this.map.once("style.load", run);
  }

  #styleParsed() {
    try {
      return Array.isArray(this.map.getStyle()?.layers);
    } catch {
      return false;
    }
  }

  // No GeolocateControl on purpose: prompting for the viewer's own position on
  // a page about someone's location history is the wrong default. Attribution
  // still comes from the style document, never a hand-written string; it is
  // added compact and collapsed so it does not cover the track, and expands on
  // click. It survives even when the interactive controls are switched off.
  // A world image source carries no attribution of its own, so the world's
  // credit is handed to the control directly.
  #addControls() {
    const { NavigationControl, FullscreenControl, ScaleControl, AttributionControl } = this.maplibre;

    if (this.controlsValue) {
      this.map.addControl(new NavigationControl({ visualizePitch: true }), "top-right");
      this.map.addControl(new FullscreenControl(), "top-right");
    }
    const attribution = this.hasVirtualBasemapValue ? this.virtualBasemapValue.attribution : undefined;
    this.map.addControl(new AttributionControl({ compact: true, customAttribution: attribution }), "bottom-right");
    collapseAttribution(this.map, this.mapElement);
    if (this.controlsValue) {
      this.map.addControl(
        new ScaleControl({ unit: this.unitSystemValue === "imperial" ? "imperial" : "metric" }),
        "bottom-left",
      );
    }
  }

  #basemapTheme() {
    return resolveBasemapTheme(this.basemapThemeValue, documentTheme());
  }

  #styleUrlForTheme(theme) {
    return theme === "dark" && this.#hasDarkStyle() ? this.styleUrlDarkValue : this.styleUrlValue;
  }

  // False when both themes resolve to the same document, which is what an
  // operator self-hosting a single style gets. There is then nothing to swap.
  #hasDarkStyle() {
    return this.hasStyleUrlDarkValue &&
      Boolean(this.styleUrlDarkValue) &&
      this.styleUrlDarkValue !== this.styleUrlValue;
  }

  async #applyTheme(theme) {
    if (!this.map) return;
    // A world image is one picture for both themes: the dark variant dims it
    // rather than swapping a style document.
    if (this.hasVirtualBasemapValue) {
      this.#applyWorldTheme(theme);
      return;
    }
    if (!this.#hasDarkStyle()) return;

    const url = this.#styleUrlForTheme(theme);
    // Also the guard that makes calling this after the initial draw a no-op.
    if (url === this.currentStyleUrl) return;

    this.currentStyleUrl = url;
    const style = await this.#loadStyle(url);
    if (!this.connected || this.currentStyleUrl !== url) return;

    // setStyle replaces the whole style document, discarding sources and layers
    // added at runtime. Without transformStyle the basemap would change and the
    // route would silently vanish. Markers are DOM, not style, and survive.
    this.map.setStyle(style, {
      transformStyle: (previous, next) => this.#carryOverlays(previous, next),
    });
  }

  // The style a virtual world draws: its own colour around the image, then the
  // image stretched over the world's rectangle. No tiles, no third-party
  // request, and the track layers are added on top exactly as on a basemap.
  #worldStyle(theme) {
    return worldStyle(this.virtualBasemapValue, theme);
  }

  #applyWorldTheme(theme) {
    if (!this.map?.getLayer(WORLD_LAYER_ID)) return;
    for (const [property, value] of Object.entries(worldPaint(theme))) {
      this.map.setPaintProperty(WORLD_LAYER_ID, property, value);
    }
    this.map.setPaintProperty(
      WORLD_BACKGROUND_LAYER_ID, "background-color", worldBackground(this.virtualBasemapValue, theme)
    );
  }

  #carryOverlays(previous, next) {
    if (!previous) return next;

    const ours = [...this.trackLayerIds, ANOMALY_LAYER, ANOMALY_POINT_LAYER, SELECTION_LAYER, DIRECTION_LAYER_ID, TRACK_HIT_LAYER]
      .map((id) => previous.layers.find((layer) => layer.id === id))
      .filter(Boolean);

    // Re-anchor rather than append: the new style has its own geometry and
    // label layers, and the route belongs above the geometry just as it did on
    // the old style.
    const layers = [...next.layers];
    const anchor = overlayAnchorLayerId(layers);
    const anchorIndex = anchor === undefined ? -1 : layers.findIndex((layer) => layer.id === anchor);
    layers.splice(anchorIndex === -1 ? layers.length : anchorIndex, 0, ...ours);

    const sources = { ...next.sources };
    for (const id of [TRACK_SOURCE, ANOMALY_SOURCE, SELECTION_SOURCE, DIRECTION_SOURCE]) {
      if (previous.sources[id]) sources[id] = previous.sources[id];
    }

    return { ...next, sources, layers };
  }

  async #loadStyle(url) {
    if (!url) return BLANK_STYLE;

    try {
      const response = await fetch(url, { signal: this.abortController.signal });
      if (!response.ok) throw new Error(`Style request failed with ${response.status}`);

      return await response.json();
    } catch {
      return BLANK_STYLE;
    }
  }

  // Returns the track features, or null when the track could not be read. Null
  // is an error the user must see; an empty list is a valid empty track.
  async #loadTrack() {
    if (this.hasGeojsonValue) {
      const inline = this.geojsonValue;
      if (inline?.type === "FeatureCollection" && Array.isArray(inline.features)) {
        return inline.features;
      }
    }

    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "application/geo+json" },
        signal: this.abortController.signal,
      });
      if (!response.ok) throw new Error(`Track request failed with ${response.status}`);

      const data = await response.json();
      if (data?.type !== "FeatureCollection" || !Array.isArray(data.features)) {
        throw new Error("Invalid track response");
      }

      return data.features;
    } catch {
      return null;
    }
  }

  #draw(features) {
    const segments = features
      .map((feature, index) => this.#prepareSegment(feature, index))
      .filter((segment) => segment.coordinates.length > 1);
    this.segments = segments;
    this.metricRanges = {};

    if (segments.length === 0) {
      this.#showState("empty");
      return;
    }

    // One Feature per recording segment, never one joined line: a pause must
    // not draw a straight line across the gap.
    //
    // lineMetrics is what makes ["line-progress"] available, which the metric
    // gradient interpolates over.
    this.map.addSource(TRACK_SOURCE, {
      type: "geojson",
      lineMetrics: true,
      data: this.#collectionOf(segments),
    });

    // A gradient is a layer-wide paint property while line-progress runs 0 to 1
    // along each individual feature, so one layer per segment is the only way a
    // multi-segment track can carry a gradient that means anything. Each layer
    // is filtered to its own feature.
    this.trackLayerIds = segments.map((segment) => this.#trackLayerId(segment.index));
    segments.forEach((segment) => {
      this.map.addLayer({
        id: this.#trackLayerId(segment.index),
        type: "line",
        source: TRACK_SOURCE,
        filter: ["==", ["get", "segment_index"], segment.index],
        layout: { "line-cap": "round", "line-join": "round" },
        paint: { "line-width": 4, "line-opacity": 0.9, "line-color": this.#trackColor() },
      }, this.#overlayAnchorLayerId());
    });
    this.#paintTrack();
    this.#syncMetricControl();
    this.#addAnomalyLayers();

    this.map.addSource(SELECTION_SOURCE, { type: "geojson", data: EMPTY_COLLECTION });
    this.map.addLayer({
      id: SELECTION_LAYER,
      type: "line",
      source: SELECTION_SOURCE,
      layout: { "line-cap": "round", "line-join": "round" },
      paint: { "line-color": this.#selectionColor(), "line-width": 8, "line-opacity": 0.8 },
    }, this.#overlayAnchorLayerId());

    // Above the track and the ink highlight: the sense of travel must stay
    // readable while a lap or a segment range is being inspected. The anchors
    // are computed rather than laid out by MapLibre so a chevron can move off
    // a corner; the source is filled once the fitted zoom is known below.
    this.#registerDirectionImage();
    this.map.addSource(DIRECTION_SOURCE, { type: "geojson", data: EMPTY_COLLECTION });
    this.map.addLayer(directionLayer({ source: DIRECTION_SOURCE }), this.#overlayAnchorLayerId());

    // A transparent, wider copy of the track catches the pointer around the
    // line; the visible layers stay 4px. It shares TRACK_SOURCE, so smoothing
    // and metric changes update it for free, and it must stay above them for
    // the whole style lifetime (#carryOverlays keeps its place on a theme swap).
    this.map.addLayer({
      id: TRACK_HIT_LAYER,
      type: "line",
      source: TRACK_SOURCE,
      layout: { "line-cap": "round", "line-join": "round" },
      paint: { "line-width": TRACK_HOVER_HIT_WIDTH, "line-opacity": 0 },
    }, this.#overlayAnchorLayerId());

    this.#addMarkers(segments);
    this.#watchHover();
    this.map.fitBounds(this.#boundsOf(segments), { padding: FIT_PADDING, animate: false });
    this.#refreshDirections();
    this.#showState("ready");

    if (this.selection) this.#drawSelection(this.selection);
    if (this.highlightRange) this.#drawHighlight(this.highlightRange);
    this.#renderStopMarkers();
    this.#renderWeatherMarkers();
    this.#renderPhotoMarkers();
  }

  // The photo gallery republishes its placed photos after every change.
  photosChanged(event) {
    const markers = event.detail?.markers;
    if (!Array.isArray(markers)) return;
    this.photosValue = markers;
    this.#renderPhotoMarkers();
  }

  // The owner asked to drop a photo on the track: the next click on the map
  // names the spot, which the gallery snaps onto the line server-side. The
  // instruction and its error live on the map itself (DESIGN.md §10.22), with
  // « Annuler » beside them; Escape cancels too.
  photoPlace(event) {
    const detail = event.detail ?? {};
    if (!this.map || typeof detail.id !== "string") return;

    this.#armPhotoPlacement(detail.id, detail.prompt, "");
  }

  // A click beside the line: the server refused it, and the map says why and
  // stays armed for the next try.
  photoPlaceError(event) {
    const detail = event.detail ?? {};
    if (!this.map || typeof detail.id !== "string") return;

    this.#armPhotoPlacement(detail.id, detail.prompt, detail.message);
  }

  cancelPhotoPlacement() {
    if (!this.placingPhoto) return;

    const detail = { id: this.placingPhoto, cancelled: true };
    this.#stopPlacing();
    window.dispatchEvent(new CustomEvent("allure:photo-placed", { detail }));
  }

  // The lightbox's « Voir sur la carte »: the marker is the same photo, so the
  // map flies to it and pulses it once.
  photoFocus(event) {
    const id = event.detail?.id;
    if (!this.map || typeof id !== "string") return;

    const photo = (this.photosValue ?? []).find((candidate) => candidate.id === id);
    if (!photo) return;

    this.mapElement.scrollIntoView({ behavior: "smooth", block: "center" });
    this.map.flyTo({ center: [Number(photo.lon), Number(photo.lat)], zoom: Math.max(this.map.getZoom(), 14) });
    const marker = this.mapElement.querySelector(`.allure-map-photo[data-photo-ids~="${CSS.escape(id)}"]`);
    if (!marker) return;

    marker.classList.add("allure-map-photo--active");
    window.clearTimeout(this.photoPulseTimer);
    this.photoPulseTimer = window.setTimeout(() => marker.classList.remove("allure-map-photo--active"), 2400);
  }

  #armPhotoPlacement(id, prompt, error) {
    this.#stopPlacing();
    this.placingPhoto = id;
    this.map.getCanvas().style.cursor = "crosshair";
    this.mapElement.classList.add("allure-map--placing");
    this.#showPlacingOverlay(prompt, error);
    this.placingClick = (clickEvent) => {
      const detail = { id: this.placingPhoto, longitude: clickEvent.lngLat.lng, latitude: clickEvent.lngLat.lat };
      this.#stopPlacing();
      window.dispatchEvent(new CustomEvent("allure:photo-placed", { detail }));
    };
    this.placingKey = (keyEvent) => {
      if (keyEvent.key !== "Escape") return;
      this.cancelPhotoPlacement();
    };
    this.map.once("click", this.placingClick);
    window.addEventListener("keydown", this.placingKey);
  }

  #showPlacingOverlay(prompt, error) {
    if (!this.hasPlacingTarget) return;

    this.placingTarget.hidden = false;
    this.placingTarget.classList.toggle("allure-map__placing--error", Boolean(error));
    if (this.hasPlacingTextTarget) this.placingTextTarget.textContent = error || prompt || "";
  }

  #hidePlacingOverlay() {
    if (!this.hasPlacingTarget) return;

    this.placingTarget.hidden = true;
    this.placingTarget.classList.remove("allure-map__placing--error");
  }

  #stopPlacing() {
    if (this.placingClick) this.map?.off("click", this.placingClick);
    if (this.placingKey) window.removeEventListener("keydown", this.placingKey);
    this.placingClick = null;
    this.placingKey = null;
    this.placingPhoto = null;
    if (this.map) this.map.getCanvas().style.cursor = "";
    this.mapElement?.classList.remove("allure-map--placing");
    this.#hidePlacingOverlay();
  }

  // Greedy grouping in screen space at the current zoom: a photo joins the
  // first group whose anchor lies within the marker's size. Recomputed on
  // zoom only, since a pan moves every marker together.
  #renderPhotoMarkers() {
    this.photoMarkers?.forEach((marker) => marker.remove());
    this.photoMarkers = [];
    if (!this.map || !this.maplibre) return;

    const groups = [];
    for (const photo of this.photosValue ?? []) {
      const lon = Number(photo?.lon);
      const lat = Number(photo?.lat);
      if (!Number.isFinite(lon) || !Number.isFinite(lat) || typeof photo.thumbnail !== "string") continue;

      const point = this.map.project([lon, lat]);
      const group = groups.find((candidate) => Math.hypot(candidate.point.x - point.x, candidate.point.y - point.y) < PHOTO_CLUSTER_PIXELS);
      if (group) group.photos.push({ ...photo, lon, lat });
      else groups.push({ point, photos: [{ ...photo, lon, lat }] });
    }

    for (const group of groups) {
      const [first] = group.photos;
      const element = document.createElement("button");
      element.type = "button";
      element.className = "allure-map-photo";
      // The lightbox's map link finds the group holding its photo by id.
      element.dataset.photoIds = group.photos.map((photo) => photo.id).join(" ");
      const label = group.photos.map((photo) => photo.label).filter(Boolean).join(" · ");
      element.setAttribute("aria-label", label);
      element.title = label;
      const image = document.createElement("img");
      image.src = first.thumbnail;
      image.alt = "";
      image.loading = "lazy";
      element.append(image);
      if (group.photos.length > 1) {
        const count = document.createElement("span");
        count.className = "allure-map-photo-count";
        count.textContent = String(group.photos.length);
        element.append(count);
      }
      element.addEventListener("click", (event) => {
        event.stopPropagation();
        this.#openPhotoGroup(group.photos);
      });
      this.photoMarkers.push(new this.maplibre.Marker({ element }).setLngLat([first.lon, first.lat]).addTo(this.map));
    }
  }

  // One photo opens; a group zooms in until it splits, and opens its first
  // photo once the map cannot zoom further apart.
  #openPhotoGroup(photos) {
    if (photos.length === 1 || this.map.getZoom() >= this.map.getMaxZoom() - 0.5) {
      window.dispatchEvent(new CustomEvent("allure:photo-open", { detail: { id: photos[0].id } }));
      return;
    }

    const bounds = new this.maplibre.LngLatBounds();
    photos.forEach((photo) => bounds.extend([photo.lon, photo.lat]));
    this.map.fitBounds(bounds, { padding: FIT_PADDING, maxZoom: this.map.getMaxZoom() });
  }

  // Keeps our track and selection layers above every basemap geometry layer
  // (bridges, buildings, roads, railways) while the trailing label run stays on
  // top. Resolved from the live style rather than hardcoded, because the light
  // and dark basemaps do not share layer ids.
  #overlayAnchorLayerId() {
    return overlayAnchorLayerId(this.map.getStyle().layers);
  }

  #trackLayerId(index) {
    return `${TRACK_LAYER_PREFIX}-${index}`;
  }

  #registerDirectionImage() {
    if (!this.map) return;

    ensureDirectionImage(this.map, {
      surface: cssColor("--body-bg", "#ffffff", { within: this.mapElement }),
      track: this.#trackColor(),
      devicePixelRatio: window.devicePixelRatio,
    });
  }

  #refreshDirections() {
    this.map?.getSource(DIRECTION_SOURCE)?.setData(this.#directionCollection());
  }

  // Anchors are geographic points carrying a map-space angle, recomputed only
  // when the zoom changes. One projection frame for every recording segment
  // lets a lap resumed after a gap share the first pass's direction marks.
  #directionCollection() {
    if (!this.map || !this.segments) return EMPTY_COLLECTION;

    const features = geographicChevronFeatures(
      this.segments.map((segment) => segment.coordinates),
      { zoom: this.map.getZoom() },
    );
    return directionFeatureCollection(features);
  }

  // Same point count in, same point count out: the metric arrays and the
  // distance lookups stay index-aligned with the coordinates.
  #displayCoordinates(coordinates) {
    if (this.activeSmoothing === "off") return coordinates;
    return smoothCoordinates(coordinates, { level: this.activeSmoothing });
  }

  #accountSmoothingLevel() {
    return validSmoothingLevel(this.smoothingLevelValue) ? this.smoothingLevelValue : "medium";
  }

  // Redraws the track source from the recorded geometry and re-applies every
  // geometry-derived overlay. Endpoints are fixed by the transform, so the
  // fitted bounds and the start/finish markers never move.
  #applySmoothing() {
    if (!this.map || !this.segments) return;

    this.segments.forEach((segment) => {
      segment.coordinates = this.#displayCoordinates(segment.rawCoordinates);
    });
    this.map.getSource(TRACK_SOURCE)?.setData(this.#collectionOf(this.segments));
    this.map.getSource(ANOMALY_SOURCE)?.setData(this.#anomalyCollection());
    this.#refreshDirections();

    this.hoverMarker?.remove();
    this.hoverMarker = null;
    if (this.selection) this.#drawSelection(this.selection);
    if (this.highlightRange) this.#drawHighlight(this.highlightRange);
    this.#renderStopMarkers();
    this.#renderWeatherMarkers();
  }

  #persistSmoothing(enabled) {
    if (!this.hasSmoothingPersistUrlValue) return;

    fetch(this.smoothingPersistUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content ?? "",
      },
      body: JSON.stringify({ smooth_tracks: enabled }),
    }).catch(() => {
      // The map has already switched; only the cross-device preference is lost.
    });
  }

  // Coordinates and the metric arrays that describe them have to stay index
  // aligned, so the same points dropped from the geometry are dropped from the
  // metrics. Discarding a point from one and not the other would shift every
  // colour after it.
  #prepareSegment(feature, index) {
    const raw = Array.isArray(feature?.geometry?.coordinates) ? feature.geometry.coordinates : [];
    const properties = feature?.properties ?? {};

    const kept = [];
    raw.forEach((point, position) => {
      if (Array.isArray(point) && point.length >= 2 &&
          Number.isFinite(point[0]) && Number.isFinite(point[1])) {
        kept.push(position);
      }
    });

    const align = (values) => (Array.isArray(values) ? kept.map((position) => values[position]) : null);
    const rawCoordinates = this.#unwrapSegment(kept.map((position) => raw[position]));

    return {
      index: Number.isInteger(properties.segment_index) ? properties.segment_index : index,
      rawCoordinates,
      coordinates: this.#displayCoordinates(rawCoordinates),
      distance: align(properties.distance),
      metrics: {
        elevation: align(properties.elevation),
        speed: align(properties.speed),
        power: align(properties.power),
      },
    };
  }

  #collectionOf(segments) {
    return {
      type: "FeatureCollection",
      features: segments.map((segment) => ({
        type: "Feature",
        geometry: { type: "LineString", coordinates: segment.coordinates },
        properties: { segment_index: segment.index },
      })),
    };
  }

  #boundsOf(segments) {
    const bounds = new this.maplibre.LngLatBounds();
    segments.forEach((segment) => segment.coordinates.forEach((point) => bounds.extend(point)));
    return bounds;
  }

  #addMarkers(segments) {
    const first = segments[0].coordinates;
    const last = segments[segments.length - 1].coordinates;
    this.#addMarker(first[0], "allure-map-marker--start", this.startLabelValue);
    this.#addMarker(last[last.length - 1], "allure-map-marker--finish", this.finishLabelValue);
  }

  #addMarker(coordinates, modifier, label) {
    const element = document.createElement("div");
    element.className = `allure-map-marker ${modifier}`;
    if (label) {
      element.title = label;
      element.setAttribute("aria-label", label);
    }

    this.markers.push(new this.maplibre.Marker({ element }).setLngLat(coordinates).addTo(this.map));
  }

  // Publishes the pointer's position along the route so the elevation chart can
  // mark it. Only the track layers are watched, so moving over the basemap does
  // not report a position.
  #watchHover() {
    this.map.on("mousemove", TRACK_HIT_LAYER, (event) => this.#pointerMoved(event));
    this.map.on("mouseenter", TRACK_HIT_LAYER, () => this.#setHoverCursor(true));
    this.map.on("mouseleave", TRACK_HIT_LAYER, () => {
      this.#setHoverCursor(false);
      this.#moveHoverMarker(null);
      this.#publishHover(null);
    });
  }

  // Inside the hit band the ball is the cursor, so the arrow is hidden; outside
  // it the map keeps its own cursor.
  #setHoverCursor(hidden) {
    const canvas = this.map?.getCanvas();
    if (canvas) canvas.style.cursor = hidden ? "none" : "";
  }

  #pointerMoved(event) {
    const feature = event.features?.[0];
    if (!feature) return;

    const segment = this.segments?.find((it) => it.index === feature.properties?.segment_index);
    const distance = segment ? this.#distanceNearest(segment, event.lngLat) : null;
    // The same snapped vertex the profile cursor uses, so the two balls are one.
    // Re-assert the hidden pointer on every move: MapLibre's own drag handlers
    // write the canvas cursor, and the band must win while it is hovered.
    this.#setHoverCursor(true);
    const coordinates = Number.isFinite(distance) ? this.#coordinatesAtDistance(distance) : null;
    this.#moveHoverMarker(coordinates);
    this.#publishHover(distance);
  }

  // Nearest point by straight-line comparison in degrees, with longitude scaled
  // by latitude so a degree east is weighted like a degree north. Exact geodesic
  // distance would not change which point wins.
  #distanceNearest(segment, lngLat) {
    if (!segment.distance) return null;

    const scale = Math.cos((lngLat.lat * Math.PI) / 180);
    let closest = -1;
    let smallest = Infinity;

    segment.coordinates.forEach((coordinate, position) => {
      const dx = (coordinate[0] - lngLat.lng) * scale;
      const dy = coordinate[1] - lngLat.lat;
      const squared = dx * dx + dy * dy;
      if (squared < smallest) {
        smallest = squared;
        closest = position;
      }
    });

    return closest === -1 ? null : segment.distance[closest];
  }

  #publishHover(distance) {
    const detail = Number.isFinite(distance)
      ? { source: "map", distance }
      : { source: "map", clear: true };

    window.dispatchEvent(new CustomEvent(TRACK_HOVER, { detail }));
  }

  // Distances are cumulative across the whole workout and therefore sorted, so
  // the matching point is a binary search. A distance falling inside a recording
  // gap belongs to no segment and clears the marker.
  #coordinatesAtDistance(distance) {
    for (const segment of this.segments ?? []) {
      const distances = segment.distance;
      if (!distances || distances.length === 0) continue;
      if (distance < distances[0] || distance > distances[distances.length - 1]) continue;

      let low = 0;
      let high = distances.length - 1;
      while (low < high) {
        const middle = (low + high) >> 1;
        if (distances[middle] < distance) low = middle + 1;
        else high = middle;
      }
      return segment.coordinates[low];
    }

    return null;
  }

  #moveHoverMarker(coordinates) {
    if (!coordinates) {
      this.hoverMarker?.remove();
      this.hoverMarker = null;
      return;
    }

    if (!this.hoverMarker) {
      const element = document.createElement("div");
      element.className = "allure-map-marker allure-map-marker--hover";
      this.hoverMarker = new this.maplibre.Marker({ element });
    }

    this.hoverMarker.setLngLat(coordinates).addTo(this.map);
  }

  // One small stop panel per stop while the stops tab is active. The duration
  // bubble stays hidden until the row is hovered, focused, or pinned.
  #renderStopMarkers() {
    this.stopMarkers?.forEach((marker) => marker.remove());
    this.stopMarkers = [];
    if (!this.map || !this.maplibre) return;

    for (const entry of this.stopMarkerData ?? []) {
      const coordinates = this.#coordinatesAtDistance(Number(entry.distance));
      if (!coordinates) continue;

      const element = document.createElement("div");
      element.className = "allure-map-marker allure-map-marker--stop";
      const icon = document.createElement("i");
      icon.className = "ti ti-player-pause";
      icon.setAttribute("aria-hidden", "true");
      element.append(icon);
      if (entry.label) {
        const label = document.createElement("span");
        label.className = "allure-map-stop-label";
        label.textContent = entry.label;
        element.append(label);
      }

      const marker = new this.maplibre.Marker({ element })
        .setLngLat(coordinates)
        .addTo(this.map);
      marker.stopDistance = Number(entry.distance);
      this.stopMarkers.push(marker);
    }
    this.#applyStopHighlight();
  }

  // One small weather panel per change of weather: the condition icon, the
  // temperature and an arrow pointing where the wind blows. The arrow is
  // counter-rotated by the map's bearing, so it stays true to north.
  #renderWeatherMarkers() {
    this.weatherMarkers?.forEach((marker) => marker.remove());
    this.weatherMarkers = [];
    if (!this.map || !this.maplibre) return;

    for (const entry of this.weatherMarkerData ?? []) {
      const coordinates = this.#coordinatesAtDistance(Number(entry.distance));
      if (!coordinates) continue;

      const description = [entry.name, entry.label].filter(Boolean).join(" · ");
      const element = document.createElement("div");
      element.className = "allure-map-marker allure-map-marker--weather";
      element.setAttribute("role", "img");
      element.setAttribute("aria-label", description);
      element.title = description;
      // The white Meteocons icon on the rose pill, animated unless the reader
      // asked for less motion (PLAN_WEATHER.md §7).
      const icon = document.createElement("img");
      icon.className = "allure-map-weather-icon";
      icon.src = weatherIconUrl(entry.svg, { color: "#ffffff" }) ?? "";
      icon.alt = "";
      icon.setAttribute("aria-hidden", "true");
      element.append(icon);
      if (entry.temperature) {
        const label = document.createElement("span");
        label.className = "allure-map-weather-label";
        label.textContent = entry.temperature;
        element.append(label);
      }
      const direction = Number(entry.wind_direction);
      if (entry.wind_direction !== null && entry.wind_direction !== undefined && Number.isFinite(direction)) {
        const arrow = document.createElement("i");
        arrow.className = "ti ti-arrow-narrow-up allure-map-weather-wind";
        arrow.setAttribute("aria-hidden", "true");
        arrow.dataset.windTo = String((direction + 180) % 360);
        element.append(arrow);
      }

      this.weatherMarkers.push(new this.maplibre.Marker({ element }).setLngLat(coordinates).addTo(this.map));
    }
    this.#orientWeatherArrows();
  }

  #orientWeatherArrows() {
    const bearing = this.map?.getBearing?.() ?? 0;
    this.weatherMarkers?.forEach((marker) => {
      const arrow = marker.getElement().querySelector(".allure-map-weather-wind");
      if (arrow) arrow.style.transform = `rotate(${Number(arrow.dataset.windTo) - bearing}deg)`;
    });
  }

  #applyStopHighlight() {
    const active = this.highlightSource === "stop" && this.highlightRange
      ? this.highlightRange.start
      : null;
    this.stopMarkers?.forEach((marker) => {
      const selected = active !== null && Math.abs(marker.stopDistance - active) <= 1.0;
      marker.getElement().classList.toggle("allure-map-marker--stop-active", selected);
    });
  }

  // Repaints every track layer for the active metric. With the flat default,
  // and for a segment with nothing to show for a chosen metric, the layer
  // keeps the brand line rather than disappearing.
  #paintTrack() {
    if (!this.map || !this.segments) return;

    const range = this.#metricRange(this.metric);
    this.segments.forEach((segment) => {
      const id = this.#trackLayerId(segment.index);
      if (!this.map.getLayer(id)) return;

      const gradient = this.#gradientFor(segment, range);
      // The two are mutually exclusive: MapLibre rejects a layer carrying both.
      if (gradient) {
        this.map.setPaintProperty(id, "line-color", undefined);
        this.map.setPaintProperty(id, "line-gradient", gradient);
      } else {
        this.map.setPaintProperty(id, "line-gradient", undefined);
        this.map.setPaintProperty(id, "line-color", this.#trackColor());
      }
    });
  }

  // Normalised across the whole workout, not per segment, so the same colour
  // means the same altitude on every part of the track. Elevation keeps its
  // true extremes; speed and power span the bulk of their readings, so one
  // stop or one sprint does not flatten the rest of the ride.
  #metricRange(metric) {
    this.metricRanges ??= {};
    if (metric in this.metricRanges) return this.metricRanges[metric];

    const values = [];
    for (const segment of this.segments ?? []) {
      for (const value of segment.metrics[metric] ?? []) {
        if (Number.isFinite(value)) values.push(value);
      }
    }

    const range = this.#rangeOf(metric, values);
    this.metricRanges[metric] = range;
    return range;
  }

  #rangeOf(metric, values) {
    if (values.length === 0) return null;

    let min = Infinity;
    let max = -Infinity;
    for (const value of values) {
      if (value < min) min = value;
      if (value > max) max = value;
    }
    if (ROBUST_METRICS.has(metric)) [min, max] = robustExtent(values);

    // A metric that never varies carries no information worth colouring.
    return max > min ? { min, max } : null;
  }

  #gradientFor(segment, range) {
    const values = segment.metrics[this.metric];
    const distance = segment.distance;
    if (!range || !values || !distance || values.length < 2) return null;

    const first = distance[0];
    const span = distance[distance.length - 1] - first;
    if (!Number.isFinite(span) || span <= 0) return null;

    const stops = BINNED_METRICS.has(this.metric)
      ? this.#binnedStops(values, distance, first, span, range)
      : this.#sampledStops(values, distance, first, span, range);

    if (stops.length < 4) return null;

    return ["interpolate", ["linear"], ["line-progress"], ...stops];
  }

  // One reading per stop, which preserves an elevation profile's summits.
  #sampledStops(values, distance, first, span, range) {
    const count = Math.min(GRADIENT_STOPS, values.length);
    const stops = [];
    let previous = -1;

    for (let step = 0; step < count; step += 1) {
      const at = Math.round((step * (values.length - 1)) / (count - 1));
      const value = values[at];
      if (!Number.isFinite(value) || !Number.isFinite(distance[at])) continue;

      const progress = Math.min(1, Math.max(0, (distance[at] - first) / span));
      // MapLibre rejects an interpolate expression whose inputs are not strictly
      // increasing, which sampling can easily produce on a track that pauses.
      if (progress <= previous) continue;
      previous = progress;

      stops.push(progress, this.#rampColor((value - range.min) / (range.max - range.min)));
    }

    return stops;
  }

  // The mean of the readings in each stop's own slice of the route: a noisy
  // sensor's spikes average out instead of painting static.
  #binnedStops(values, distance, first, span, range) {
    const count = Math.min(GRADIENT_STOPS, values.length);
    const sums = new Array(count).fill(0);
    const counts = new Array(count).fill(0);
    const positions = new Array(count).fill(0);

    for (let index = 0; index < values.length; index += 1) {
      const value = values[index];
      const at = distance[index];
      if (!Number.isFinite(value) || !Number.isFinite(at)) continue;

      const progress = Math.min(1, Math.max(0, (at - first) / span));
      const bin = Math.min(count - 1, Math.floor(progress * count));
      sums[bin] += value;
      counts[bin] += 1;
      positions[bin] += progress;
    }

    const stops = [];
    let previous = -1;
    for (let bin = 0; bin < count; bin += 1) {
      if (counts[bin] === 0) continue;

      const progress = positions[bin] / counts[bin];
      if (progress <= previous) continue;
      previous = progress;

      stops.push(progress, this.#rampColor((sums[bin] / counts[bin] - range.min) / (range.max - range.min)));
    }

    return stops;
  }

  #rampColor(position) {
    const ramp = this.#ramp();
    const scaled = Math.min(1, Math.max(0, position)) * (ramp.length - 1);
    const lower = Math.floor(scaled);
    const upper = Math.min(ramp.length - 1, lower + 1);

    return this.#mix(ramp[lower], ramp[upper], scaled - lower);
  }

  #ramp() {
    if (this.rampCache) return this.rampCache;

    // Light to dark shading of the brand primary, so a chosen metric reads as
    // intensity of one colour instead of a second palette.
    const base = parseColour(cssColor("--primary", "#c5426c"));
    this.rampCache = [
      rgbToHex(mixRgb(base, [ 255, 255, 255 ], 0.72)),
      rgbToHex(mixRgb(base, [ 255, 255, 255 ], 0.42)),
      rgbToHex(base),
      rgbToHex(mixRgb(base, [ 0, 0, 0 ], 0.25)),
      rgbToHex(mixRgb(base, [ 0, 0, 0 ], 0.48)),
    ];
    return this.rampCache;
  }

  #mix(from, to, amount) {
    const channels = [1, 3, 5].map((offset) => {
      const start = parseInt(from.slice(offset, offset + 2), 16);
      const end = parseInt(to.slice(offset, offset + 2), 16);
      return Math.round(start + (end - start) * amount);
    });

    return `rgb(${channels.join(",")})`;
  }

  // The selector offers the solid line plus every metric that actually
  // varies; it disappears only when no metric can be chosen.
  #syncMetricControl() {
    if (!this.hasMetricTarget) return;

    const available = METRICS.filter((metric) => this.#metricRange(metric));
    this.metricTarget.hidden = available.length === 0;

    for (const option of this.metricTarget.options) {
      option.hidden = option.value !== FLAT_METRIC && !available.includes(option.value);
    }
    if (this.metric !== FLAT_METRIC && !available.includes(this.metric)) {
      this.metric = FLAT_METRIC;
    }
    this.metricTarget.value = this.metric;
    this.#renderLegend();
  }

  // The colour-by legend (DESIGN.md §15.2): the selected metric's ramp and its
  // two ends, in the viewer's own units. Hidden for the flat line.
  #renderLegend() {
    if (!this.hasLegendTarget) return;

    const entry = this.legendLocaleValue?.[this.metric];
    const range = this.metric === FLAT_METRIC ? null : this.#metricRange(this.metric);
    if (!entry || !range) {
      this.legendTarget.hidden = true;
      return;
    }

    this.legendTarget.hidden = false;
    this.legendTitleTarget.textContent = entry.label;
    this.legendRampTarget.style.background = `linear-gradient(90deg, ${this.#ramp().join(", ")})`;
    this.legendLowTarget.textContent = this.#legendReading(this.metric, range.min, entry.unit);
    this.legendHighTarget.textContent = this.#legendReading(this.metric, range.max, entry.unit);
  }

  // The track carries SI readings; the legend prints the viewer's units.
  #legendReading(metric, value, unit) {
    let converted = value;
    if (metric === "speed") {
      converted = value * (this.unitSystemValue === "imperial" ? 2.2369362921 : 3.6);
    } else if (metric === "elevation" && this.unitSystemValue === "imperial") {
      converted = value * 3.28084;
    }

    const digits = metric === "speed" ? 1 : 0;
    const formatted = new Intl.NumberFormat(document.documentElement.lang || undefined, {
      minimumFractionDigits: digits,
      maximumFractionDigits: digits,
    }).format(converted);

    return `${formatted} ${unit}`;
  }

  // The colour choice is remembered per kind of map, like the elevation
  // chart's secondary series: a virtual ride keeps its own default instead of
  // inheriting an outdoor ride's choice, and the reverse.
  #metricStorageKey() {
    return this.powerLedValue ? "allure:map-colour:power-led" : "allure:map-colour";
  }

  #restoreMetric() {
    if (!this.hasMetricTarget) return;

    try {
      const saved = localStorage.getItem(this.#metricStorageKey());
      if (saved === FLAT_METRIC || METRICS.includes(saved)) this.metric = saved;
    } catch {
      // Storage can be disabled without disabling the map.
    }
  }

  #storeMetric() {
    if (!this.hasMetricTarget) return;

    try {
      localStorage.setItem(this.#metricStorageKey(), this.metric);
    } catch {
      // Storage can be disabled without disabling the map.
    }
  }

  #drawSelection(selection) {
    const coordinates = this.#coordinatesForRange(selection.startIndex, selection.endIndex);
    if (!coordinates) {
      this.#clearSelection();
      return;
    }

    this.map.getSource(SELECTION_SOURCE).setData({
      type: "Feature",
      geometry: { type: "LineString", coordinates },
      properties: {},
    });
  }

  #clearSelection() {
    this.map?.getSource(SELECTION_SOURCE)?.setData(EMPTY_COLLECTION);
  }

  // Point indexes arrive numbered across the whole workout, while coordinates
  // are stored per recording segment. A range that straddles a gap has no
  // single line to highlight and is rejected.
  #coordinatesForRange(startIndex, endIndex) {
    if (!Number.isInteger(startIndex) || !Number.isInteger(endIndex) || endIndex <= startIndex) return null;

    let offset = 0;
    for (const { coordinates } of this.segments ?? []) {
      const segmentEnd = offset + coordinates.length - 1;
      if (startIndex >= offset && endIndex <= segmentEnd) {
        return coordinates.slice(startIndex - offset, endIndex - offset + 1);
      }
      offset += coordinates.length;
    }

    return null;
  }

  #drawHighlight(range) {
    const features = [];
    for (const { start, end } of range.ranges ?? [ range ]) {
      for (const segment of this.segments ?? []) {
        const coordinates = this.#coordinatesForDistanceRange(segment, start, end);
        if (coordinates.length < 2) continue;

        features.push({
          type: "Feature",
          geometry: { type: "LineString", coordinates },
          properties: {},
        });
      }
    }

    this.map.getSource(SELECTION_SOURCE).setData({ type: "FeatureCollection", features });
  }

  // Distances are cumulative and sorted per recording segment, so both ends are
  // a binary search; the end coordinates are interpolated so the highlight
  // stops exactly at the lap boundary instead of the nearest point.
  #coordinatesForDistanceRange(segment, start, end) {
    const distances = segment.distance;
    const coordinates = segment.coordinates;
    if (!distances || distances.length < 2 || !coordinates || coordinates.length < 2) return [];

    const from = Math.max(start, distances[0]);
    const to = Math.min(end, distances[distances.length - 1]);
    if (!(to > from)) return [];

    const startPosition = this.#positionAtDistance(distances, from);
    const endPosition = this.#positionAtDistance(distances, to);
    const points = [ this.#interpolatedCoordinate(segment, from, startPosition) ];
    for (let index = startPosition + 1; index < endPosition; index += 1) {
      points.push(coordinates[index]);
    }
    points.push(this.#interpolatedCoordinate(segment, to, Math.min(endPosition, distances.length - 2)));
    return points;
  }

  // Last index whose distance is at or below the target.
  #positionAtDistance(distances, target) {
    let low = 0;
    let high = distances.length - 1;
    while (low < high) {
      const middle = (low + high + 1) >> 1;
      if (distances[middle] <= target) low = middle;
      else high = middle - 1;
    }
    return low;
  }

  #interpolatedCoordinate(segment, target, position) {
    const distances = segment.distance;
    const coordinates = segment.coordinates;
    if (position >= distances.length - 1) return coordinates[coordinates.length - 1];

    const span = distances[position + 1] - distances[position];
    if (!(span > 0)) return coordinates[position];

    const ratio = Math.min(1, Math.max(0, (target - distances[position]) / span));
    const from = coordinates[position];
    const to = coordinates[position + 1];
    return [ from[0] + (to[0] - from[0]) * ratio, from[1] + (to[1] - from[1]) * ratio ];
  }
  // +180 and -180. Drawn literally that is a line all the way around the world,
  // A track crossing the antimeridian arrives with longitudes jumping between
  // +180 and -180. Drawn literally that is a line all the way around the world,
  // so each point is shifted into the same continuous frame as the one before.
  #unwrapSegment(segment) {
    const coordinates = (Array.isArray(segment) ? segment : []).filter((point) => (
      Array.isArray(point) && point.length >= 2 && Number.isFinite(point[0]) && Number.isFinite(point[1])
    ));
    if (coordinates.length === 0) return [];

    const unwrapped = [[coordinates[0][0], coordinates[0][1]]];
    for (const [rawLongitude, latitude] of coordinates.slice(1)) {
      let longitude = rawLongitude;
      const previous = unwrapped[unwrapped.length - 1][0];
      while (longitude - previous > 180) longitude -= 360;
      while (longitude - previous < -180) longitude += 360;
      unwrapped.push([longitude, latitude]);
    }
    return unwrapped;
  }

  #trackColor() {
    return cssColor("--primary", "#c5426c");
  }

  #anomalyColor() {
    return cssColor("--warning", "#f59f00");
  }

  // Short dashes in the warning colour over the stretch the reading concerns,
  // and a hollow dot on each position the analysis left out, joined to its
  // kept neighbours by the same dashes. Nothing is drawn without findings.
  #addAnomalyLayers() {
    if (this.anomaliesValue.length === 0) return;

    this.map.addSource(ANOMALY_SOURCE, { type: "geojson", data: this.#anomalyCollection() });
    this.map.addLayer({
      id: ANOMALY_LAYER,
      type: "line",
      source: ANOMALY_SOURCE,
      filter: ["==", ["geometry-type"], "LineString"],
      layout: { "line-cap": "butt", "line-join": "round" },
      paint: { "line-color": this.#anomalyColor(), "line-width": 3, "line-dasharray": [1.2, 1.2] },
    }, this.#overlayAnchorLayerId());
    this.map.addLayer({
      id: ANOMALY_POINT_LAYER,
      type: "circle",
      source: ANOMALY_SOURCE,
      filter: ["==", ["geometry-type"], "Point"],
      paint: {
        "circle-radius": 3.5,
        "circle-color": cssColor("--body-bg", "#ffffff", { within: this.mapElement }),
        "circle-stroke-color": this.#anomalyColor(),
        "circle-stroke-width": 2,
      },
    }, this.#overlayAnchorLayerId());
  }

  #anomalyCollection() {
    const features = [];
    for (const anomaly of this.anomaliesValue) {
      if (!this.inspectAnomalies && anomaly?.tier !== "major") continue;
      const label = typeof anomaly?.label === "string" ? anomaly.label : "";
      const path = this.#validCoordinates(anomaly?.path);
      const rejected = this.#validCoordinates(anomaly?.coordinates);
      if (rejected.length > 0) {
        if (path.length > 1) {
          features.push({ type: "Feature", geometry: { type: "LineString", coordinates: path }, properties: { label } });
        }
        rejected.forEach((coordinates) => {
          features.push({ type: "Feature", geometry: { type: "Point", coordinates }, properties: { label } });
        });
        continue;
      }

      const range = this.#anomalyRange(anomaly);
      if (!range) continue;
      for (const segment of this.segments ?? []) {
        const coordinates = this.#coordinatesForDistanceRange(segment, range.start, range.end);
        if (coordinates.length < 2) continue;
        features.push({ type: "Feature", geometry: { type: "LineString", coordinates }, properties: { label } });
      }
    }
    return { type: "FeatureCollection", features };
  }

  #anomalyRange(anomaly) {
    const start = Number(anomaly?.start);
    const end = Number(anomaly?.end);
    if (!Number.isFinite(start) || !Number.isFinite(end) || end < start) return null;
    if (end - start >= ANOMALY_MIN_RANGE_METRES) return { start, end };

    const middle = (start + end) / 2;
    const low = Math.max(0, middle - ANOMALY_MIN_RANGE_METRES / 2);
    return { start: low, end: low + ANOMALY_MIN_RANGE_METRES };
  }

  #validCoordinates(list) {
    if (!Array.isArray(list)) return [];
    return list.filter((point) => (
      Array.isArray(point) && point.length >= 2 && Number.isFinite(point[0]) && Number.isFinite(point[1])
    )).map((point) => [point[0], point[1]]);
  }

  #selectionColor() {
    // Ink, not primary: the track itself is primary, so the highlight must be
    // the contrasting theme colour to stay visible on it and on the ramp.
    return cssColor("--body-color", "#1f2937", { within: this.mapElement });
  }

  #showState(state) {
    if (this.hasLoadingTarget) this.loadingTarget.hidden = state !== "loading";
    if (this.hasErrorTarget) this.errorTarget.hidden = state !== "error";
    if (this.hasEmptyTarget) this.emptyTarget.hidden = state !== "empty";
    if (this.hasCanvasTarget) this.canvasTarget.hidden = state === "error" || state === "empty";
  }
}

// Accepts "#rrggbb" or an "rgb(r, g, b)" computed value.
function parseColour(value) {
  const colour = value.trim();
  if (colour.startsWith("#")) {
    return [ 1, 3, 5 ].map((offset) => parseInt(colour.slice(offset, offset + 2), 16));
  }
  return (colour.match(/[\d.]+/g) ?? []).slice(0, 3).map(Number);
}

function mixRgb(from, to, amount) {
  return from.map((channel, index) => Math.round(channel + (to[index] - channel) * amount));
}

function rgbToHex(channels) {
  return `#${channels.map((channel) => Math.max(0, Math.min(255, channel)).toString(16).padStart(2, "0")).join("")}`;
}
