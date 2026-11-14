import { Controller } from "@hotwired/stimulus";
import { cssColor } from "../lib/css_color";
import { smoothCoordinates } from "../lib/track_smoothing";
import { courseLayout, courseShadePalette, SHADE_COUNT } from "../lib/course_overlaps";
import { directionLayer, ensureDirectionImage, geographicChevronFeatures } from "../lib/direction_chevrons";
import { overlayAnchorLayerId } from "../lib/map_overlay_anchor";
import { collapseAttribution } from "../lib/map_attribution";
import { applyBasemapTheme, basemapFollowsPage, documentTheme, resolveBasemapTheme } from "../lib/basemap_theme";

// The Découvrir map (DESIGN.md §20.6): one line per course the viewer may see
// in the current viewport, refreshed as the reader moves. It owns its MapLibre
// instance exactly like the other map controllers — dynamic import, in-flight
// abort on disconnect, theme-aware style — and every popup fact comes from
// server-formatted properties drawn as text nodes, never as raw HTML. Course
// lines are smoothed at the medium level for display, like every other course
// map (DESIGN.md §15.4).
//
// Courses stacked on the same road take nuances of the primary and the
// shorter one draws on top (lib/course_overlaps); every course carries its
// direction arrows, since a segment only matches recordings made its way.
const SOURCE = "allure-segments";
const LINE_LAYER = "allure-segments-line";
const HIT_LAYER = "allure-segments-hit";
const DIRECTION_SOURCE = "allure-segments-direction";
const DIRECTION_LAYER = "allure-segments-direction-arrows";
const ARROW_IMAGE_PREFIX = "allure-segments-arrow-";
const SMOOTHING_LEVEL = "medium";
const DEFAULT_CENTRE = [2.5, 46.6];
const DEFAULT_ZOOM = 5;
const LOCATED_ZOOM = 12;
const MOVE_DEBOUNCE_MS = 250;
const FIT_PADDING = 48;
const POPUP_OFFSET = 10;
// A tap rarely lands on more stacked courses than this; the popup stays short.
const POPUP_MAX_COURSES = 6;
const BLANK_STYLE = { version: 8, sources: {}, layers: [] };
const EMPTY_COLLECTION = { type: "FeatureCollection", features: [] };

export default class extends Controller {
  static targets = ["canvas", "loading", "empty", "error", "count"];

  static values = {
    url: String,
    styleUrl: String,
    styleUrlDark: String,
    locale: Object,
    center: Array,
    countLabel: String,
    unitSystem: { type: String, default: "metric" },
    // The account's basemap preference (DESIGN.md §15.2).
    basemapTheme: { type: String, default: "auto" },
  };

  async connect() {
    this.connected = true;
    this.fitted = false;
    this.lines = [];
    this.hovered = new Set();
    this.selected = new Set();
    this.abortController = new AbortController();
    // A hover bubble only where there is a hovering pointer; touch goes
    // straight to the pinned popup.
    this.hoverCapable = window.matchMedia("(hover: hover) and (pointer: fine)").matches;
    applyBasemapTheme(this.canvasTarget, this.#basemapTheme());

    const [maplibre, { default: workerUrl }] = await Promise.all([
      import("maplibre-gl"),
      import("maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url"),
    ]);
    if (!this.connected) return;
    maplibre.setWorkerUrl(workerUrl);

    this.currentStyleUrl = this.#styleUrlForTheme(this.#basemapTheme());
    const style = await this.#loadStyle(this.currentStyleUrl);
    if (!this.connected) return;

    this.maplibre = maplibre;
    this.palette = this.#palette();
    this.map = new maplibre.Map({
      container: this.canvasTarget,
      style,
      ...this.#initialView(),
      // One finger scrolls the page and two move the map on touch screens
      // (DESIGN.md §15.2); the fullscreen control lifts it. The wheel keeps
      // zooming on a desktop: here the map is the page.
      cooperativeGestures: window.matchMedia("(pointer: coarse)").matches,
      locale: this.localeValue,
      attributionControl: false,
    });

    const { NavigationControl, FullscreenControl, ScaleControl, GeolocateControl, AttributionControl } = maplibre;
    this.map.addControl(new NavigationControl({ visualizePitch: true }), "top-right");
    // The discover map is the one map allowed to ask where the reader is
    // (PLAN_MAPLIBRE.md Slice 5): a granted permission centres it silently,
    // otherwise only this button ever prompts.
    this.locateControl = new GeolocateControl({
      positionOptions: { enableHighAccuracy: false, timeout: 8_000 },
      fitBoundsOptions: { maxZoom: LOCATED_ZOOM },
      trackUserLocation: false,
    });
    this.map.addControl(this.locateControl, "top-right");
    this.locateControl.on("geolocate", () => {
      // An explicit position wins over fitting the first payload.
      this.fitted = true;
    });
    this.map.addControl(new FullscreenControl(), "top-right");
    this.map.addControl(new AttributionControl({ compact: true }), "bottom-right");
    collapseAttribution(this.map, this.canvasTarget);
    this.map.addControl(
      new ScaleControl({ unit: this.unitSystemValue === "imperial" ? "imperial" : "metric" }),
      "bottom-left",
    );

    this.map.on("load", () => {
      this.#ensureLayers();
      this.#fetchFeatures();
      this.#maybeLocate();
    });
    // Added images belong to the style, so a basemap swap discards them.
    this.map.on("style.load", () => {
      if (!this.connected) return;
      this.#registerArrowImages();
      this.#ensureLayers();
    });
    this.map.on("styleimagemissing", (event) => {
      if (String(event?.id || "").startsWith(ARROW_IMAGE_PREFIX)) this.#registerArrowImages();
    });
    this.map.on("moveend", () => this.#scheduleFetch());
    // Arrow slots are a screen constant: only a scale change moves them.
    this.map.on("zoomend", () => this.#refreshDirections());

    this.map.on("click", HIT_LAYER, (event) => this.#pin(event));
    this.map.on("mouseenter", HIT_LAYER, () => {
      this.map.getCanvas().style.cursor = "pointer";
    });
    this.map.on("mousemove", HIT_LAYER, (event) => this.#hover(event));
    // MapLibre may deliver a mouseleave without features (the pointer left
    // while the data was replaced): the cursor and the highlight still reset.
    this.map.on("mouseleave", HIT_LAYER, () => {
      this.map.getCanvas().style.cursor = "";
      this.#setStates(this.hovered, new Set(), "hover");
      this.hovered = new Set();
      this.#removeHoverBubble();
    });
  }

  disconnect() {
    this.connected = false;
    clearTimeout(this.moveTimer);
    this.abortController?.abort();
    this.featuresAbort?.abort();
    this.hoverBubble?.remove();
    this.popup?.remove();
    this.map?.remove();
    this.map = null;
    this.maplibre = null;
    this.locateControl = null;
    this.abortController = null;
    this.featuresAbort = null;
    this.currentStyleUrl = null;
    this.hoverBubble = null;
    this.popup = null;
    this.lines = [];
  }

  // A forced basemap ignores the page theme: nothing inside the map follows it.
  themeChanged(event) {
    if (!basemapFollowsPage(this.basemapThemeValue)) return;

    const theme = resolveBasemapTheme(this.basemapThemeValue, event.detail?.theme);
    applyBasemapTheme(this.canvasTarget, theme);
    if (!this.map) return;

    this.palette = this.#palette();
    if (this.map.getLayer(LINE_LAYER)) this.map.setPaintProperty(LINE_LAYER, "line-color", this.#lineColor());
    this.#registerArrowImages({ replace: true });
    this.#applyTheme(theme);
  }

  #initialView() {
    if (this.#hasInitialCentre()) {
      return { center: this.centerValue, zoom: LOCATED_ZOOM };
    }

    return { center: DEFAULT_CENTRE, zoom: DEFAULT_ZOOM };
  }

  #hasInitialCentre() {
    return this.hasCenterValue && this.centerValue.length === 2;
  }

  // Never prompt unasked: centre silently only when the permission is already
  // granted; otherwise the control button is the single, explicit path.
  async #maybeLocate() {
    if (!navigator.geolocation || !navigator.permissions?.query) return;
    try {
      const permission = await navigator.permissions.query({ name: "geolocation" });
      if (this.connected && permission.state === "granted") this.locateControl?.trigger();
    } catch {
      // Permissions API unavailable: the button remains the only way.
    }
  }

  // Above the basemap geometry, under its trailing labels (map_overlay_anchor),
  // in this order: the lines, their arrows, then the wide invisible hit line.
  #ensureLayers() {
    if (!this.map || !this.#styleParsed()) return;

    const anchor = overlayAnchorLayerId(this.map.getStyle().layers);
    if (!this.map.getSource(SOURCE)) {
      // Keyed by the course URL so a hover or a selection survives the
      // viewport refresh.
      this.map.addSource(SOURCE, { type: "geojson", data: EMPTY_COLLECTION, promoteId: "url" });
    }
    if (!this.map.getSource(DIRECTION_SOURCE)) {
      this.map.addSource(DIRECTION_SOURCE, { type: "geojson", data: EMPTY_COLLECTION });
    }
    if (!this.map.getLayer(LINE_LAYER)) {
      const emphasised = [ "any", [ "boolean", [ "feature-state", "hover" ], false ], [ "boolean", [ "feature-state", "selected" ], false ] ];
      this.map.addLayer({
        id: LINE_LAYER,
        type: "line",
        source: SOURCE,
        // Shorter courses draw on top, so a nested climb stays visible.
        layout: { "line-cap": "round", "line-join": "round", "line-sort-key": [ "get", "sortKey" ] },
        paint: {
          "line-color": this.#lineColor(),
          // MapLibre 6 rejects feature-state inside a layer filter, so the
          // highlight is a paint expression on the single line layer.
          "line-opacity": [ "case", emphasised, 1, 0.85 ],
          "line-width": [ "case", emphasised, 6, 3 ],
        },
      }, anchor);
    }
    if (!this.map.getLayer(DIRECTION_LAYER)) {
      this.#registerArrowImages();
      // On the line itself, not beside it: a course is a thin line among
      // many, and an offset mark would read as belonging to its neighbour.
      this.map.addLayer(directionLayer({ source: DIRECTION_SOURCE, id: DIRECTION_LAYER, image: [ "get", "arrow" ], inline: true }), anchor);
    }
    if (!this.map.getLayer(HIT_LAYER)) {
      // A wide invisible line so a touch or a small course is still clickable;
      // the same sort key keeps the topmost course first under the pointer.
      this.map.addLayer({
        id: HIT_LAYER,
        type: "line",
        source: SOURCE,
        layout: { "line-cap": "round", "line-join": "round", "line-sort-key": [ "get", "sortKey" ] },
        paint: { "line-color": "transparent", "line-width": 16 },
      }, anchor);
    }
  }

  #scheduleFetch() {
    clearTimeout(this.moveTimer);
    this.moveTimer = setTimeout(() => this.#fetchFeatures(), MOVE_DEBOUNCE_MS);
  }

  async #fetchFeatures() {
    if (!this.map || !this.connected) return;

    this.featuresAbort?.abort();
    this.featuresAbort = new AbortController();
    const bounds = this.map.getBounds();
    const bbox = [
      bounds.getWest(),
      bounds.getSouth(),
      bounds.getEast(),
      bounds.getNorth(),
    ].map((value) => value.toFixed(6)).join(",");

    const url = new URL(this.urlValue, window.location.origin);
    url.searchParams.set("bbox", bbox);

    try {
      const response = await fetch(url, {
        headers: { Accept: "application/geo+json" },
        signal: this.featuresAbort.signal,
        cache: "no-store",
      });
      if (!response.ok) throw new Error(`Courses request failed with ${response.status}`);
      const collection = await response.json();
      if (!this.connected) return;
      this.#render(collection);
    } catch (error) {
      if (error.name === "AbortError" || !this.connected) return;
      this.#setState({ error: true });
    }
  }

  #render(collection) {
    const features = (Array.isArray(collection.features) ? collection.features : [])
      .filter((feature) => Array.isArray(feature?.geometry?.coordinates) && typeof feature.properties?.url === "string");
    const drawn = this.#laidOut(features);
    this.lines = drawn;
    this.map.getSource(SOURCE)?.setData({ type: "FeatureCollection", features: drawn });
    this.#refreshDirections();
    this.#setState({ loading: false, empty: drawn.length === 0, error: false });
    this.#updateCount(drawn.length);

    if (!this.fitted && !this.#hasInitialCentre() && drawn.length > 0) {
      this.fitted = true;
      this.map.fitBounds(this.#dataBounds(drawn), { padding: FIT_PADDING, animate: false });
    }
  }

  // Display-only smoothing (the course keeps the same line here as on its
  // detail page and its route image), then the stacking layout: a shade and a
  // draw order per course. The payload itself is untouched.
  #laidOut(features) {
    const smoothed = features.map((feature) => ({
      ...feature,
      geometry: {
        ...feature.geometry,
        coordinates: smoothCoordinates(feature.geometry.coordinates, { level: SMOOTHING_LEVEL }),
      },
    }));
    const layout = courseLayout(smoothed.map((feature) => feature.geometry.coordinates));

    return smoothed.map((feature, index) => ({
      ...feature,
      properties: { ...feature.properties, shade: layout[index].shade, sortKey: layout[index].sortKey, length: layout[index].length },
    }));
  }

  // Every course carries its own arrows; the longest is marked first, so a
  // shorter course on the same road and in the same direction shares its
  // marks while the opposite direction keeps its own.
  #refreshDirections() {
    if (!this.map) return;

    const ordered = [ ...this.lines ].sort((a, b) => b.properties.length - a.properties.length);
    const features = geographicChevronFeatures(
      ordered.map((feature) => feature.geometry.coordinates),
      { zoom: this.map.getZoom(), properties: (index) => ({ arrow: `${ARROW_IMAGE_PREFIX}${ordered[index].properties.shade}` }) },
    );
    this.map.getSource(DIRECTION_SOURCE)?.setData({ type: "FeatureCollection", features });
  }

  #registerArrowImages({ replace = false } = {}) {
    if (!this.map) return;

    const surface = cssColor("--body-bg", "#ffffff", { within: this.canvasTarget });
    this.palette.forEach((track, shade) => {
      const id = `${ARROW_IMAGE_PREFIX}${shade}`;
      if (replace && this.map.hasImage(id)) this.map.removeImage(id);
      ensureDirectionImage(this.map, { id, surface, track, inline: true, devicePixelRatio: window.devicePixelRatio });
    });
  }

  #palette() {
    return courseShadePalette(cssColor("--primary", "#c5426c", { within: this.canvasTarget }), this.#basemapTheme());
  }

  #lineColor() {
    const palette = this.palette;
    const branches = [];
    for (let shade = 1; shade < SHADE_COUNT; shade += 1) branches.push(shade, palette[shade]);
    return [ "match", [ "get", "shade" ], ...branches, palette[0] ];
  }

  #setState({ loading, empty, error }) {
    if (loading !== undefined) this.loadingTarget.hidden = !loading;
    if (empty !== undefined) this.emptyTarget.hidden = !empty;
    if (error !== undefined) this.errorTarget.hidden = !error;
  }

  #updateCount(count) {
    if (!this.hasCountTarget || !this.countLabelValue) return;
    this.countTarget.textContent = this.countLabelValue.replace("%{count}", String(count));
  }

  // The distinct courses under the pointer, topmost first.
  #coursesAt(event) {
    const seen = new Set();
    const courses = [];
    for (const feature of event.features || []) {
      const properties = feature?.properties;
      if (!properties?.url || seen.has(properties.url)) continue;
      seen.add(properties.url);
      courses.push(properties);
    }
    return courses.slice(0, POPUP_MAX_COURSES);
  }

  // Desktop only: the same bubble, not interactive, naming what is under the
  // pointer. A click pins it with the links (DESIGN.md §15.1: a hover and a
  // click read as the same object).
  #hover(event) {
    const courses = this.#coursesAt(event);
    const urls = new Set(courses.map((course) => course.url));
    this.#setStates(this.hovered, urls, "hover");
    this.hovered = urls;

    if (!this.hoverCapable || this.popup || courses.length === 0) {
      this.#removeHoverBubble();
      return;
    }

    const key = [ ...urls ].join("\n");
    if (!this.hoverBubble) {
      this.hoverBubble = new this.maplibre.Popup({
        offset: POPUP_OFFSET,
        closeButton: false,
        closeOnClick: false,
        focusAfterOpen: false,
        className: "allure-segments-popup-bubble allure-segments-popup-bubble--hover",
      });
      this.hoverKey = null;
    }
    if (key !== this.hoverKey) {
      this.hoverBubble.setDOMContent(this.#popupContent(courses, { interactive: false }));
      this.hoverKey = key;
    }
    this.hoverBubble.setLngLat(event.lngLat);
    if (!this.hoverBubble.isOpen()) this.hoverBubble.addTo(this.map);
  }

  #removeHoverBubble() {
    this.hoverBubble?.remove();
    this.hoverKey = null;
  }

  #pin(event) {
    const courses = this.#coursesAt(event);
    if (courses.length === 0 || !this.map) return;

    this.#removeHoverBubble();
    this.popup?.remove();

    const urls = new Set(courses.map((course) => course.url));
    const popup = new this.maplibre.Popup({
      offset: POPUP_OFFSET,
      closeButton: false,
      maxWidth: "min(20rem, calc(100vw - 2rem))",
      className: "allure-segments-popup-bubble",
    })
      .setLngLat(event.lngLat)
      .setDOMContent(this.#popupContent(courses, { interactive: true }));
    // The selected lines stay emphasised while their popup is open: on a
    // touch screen it is the only link between the popup and the map.
    popup.on("close", () => {
      if (this.popup !== popup) return;
      this.#setStates(this.selected, new Set(), "selected");
      this.selected = new Set();
      this.popup = null;
    });
    this.popup = popup;
    this.#setStates(this.selected, urls, "selected");
    this.selected = urls;
    popup.addTo(this.map);
  }

  // Facts are server-formatted strings, drawn as text nodes only.
  #popupContent(courses, { interactive }) {
    const list = document.createElement("ul");
    list.className = "allure-segments-popup";

    for (const course of courses) {
      const item = document.createElement("li");
      item.className = "allure-segments-popup__item";

      const swatch = document.createElement("span");
      swatch.className = "allure-segments-popup__swatch";
      swatch.setAttribute("aria-hidden", "true");
      swatch.style.backgroundColor = this.palette[Number(course.shade) || 0] || this.palette[0];

      const body = document.createElement("div");
      body.className = "allure-segments-popup__body";

      const name = document.createElement(interactive ? "a" : "span");
      name.className = "allure-segments-popup__name";
      if (interactive) name.href = course.url;
      name.textContent = course.name;

      const facts = document.createElement("div");
      facts.className = "allure-segments-popup__facts allure-table-nums";
      facts.textContent = [ course.sport, course.distance, course.participants ].filter(Boolean).join(" · ");

      body.append(name, facts);
      item.append(swatch, body);
      list.append(item);
    }
    return list;
  }

  #setStates(previous, next, key) {
    if (!this.map?.getSource(SOURCE)) return;
    previous.forEach((id) => {
      if (!next.has(id)) this.map.setFeatureState({ source: SOURCE, id }, { [key]: false });
    });
    next.forEach((id) => {
      if (!previous.has(id)) this.map.setFeatureState({ source: SOURCE, id }, { [key]: true });
    });
  }

  #dataBounds(features) {
    let west = Infinity;
    let south = Infinity;
    let east = -Infinity;
    let north = -Infinity;
    for (const feature of features) {
      for (const [longitude, latitude] of feature.geometry.coordinates) {
        west = Math.min(west, longitude);
        south = Math.min(south, latitude);
        east = Math.max(east, longitude);
        north = Math.max(north, latitude);
      }
    }
    return [ [ west, south ], [ east, north ] ];
  }

  #basemapTheme() {
    return resolveBasemapTheme(this.basemapThemeValue, documentTheme());
  }

  #styleUrlForTheme(theme) {
    return theme === "dark" && this.#hasDarkStyle() ? this.styleUrlDarkValue : this.styleUrlValue;
  }

  #hasDarkStyle() {
    return this.hasStyleUrlDarkValue &&
      Boolean(this.styleUrlDarkValue) &&
      this.styleUrlDarkValue !== this.styleUrlValue;
  }

  async #applyTheme(theme) {
    if (!this.map || !this.#hasDarkStyle()) return;
    const url = this.#styleUrlForTheme(theme);
    if (url === this.currentStyleUrl) return;
    this.currentStyleUrl = url;
    const style = await this.#loadStyle(url);
    if (!this.connected || this.currentStyleUrl !== url) return;
    this.map.setStyle(style, {
      transformStyle: (previous, next) => {
        if (!previous) return next;
        const layers = [...next.layers];
        const ours = [ LINE_LAYER, DIRECTION_LAYER, HIT_LAYER ]
          .map((id) => previous.layers.find((layer) => layer.id === id))
          .filter(Boolean);
        // Re-anchor rather than append: the route belongs above the new
        // style's geometry and under its labels, as on the old one.
        const anchor = overlayAnchorLayerId(layers);
        const anchorIndex = anchor === undefined ? -1 : layers.findIndex((layer) => layer.id === anchor);
        layers.splice(anchorIndex === -1 ? layers.length : anchorIndex, 0, ...ours);
        const sources = { ...next.sources };
        for (const id of [ SOURCE, DIRECTION_SOURCE ]) {
          if (previous.sources[id]) sources[id] = previous.sources[id];
        }
        return { ...next, sources, layers };
      },
    });
  }

  #styleParsed() {
    try {
      return Array.isArray(this.map.getStyle()?.layers);
    } catch {
      return false;
    }
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
}
