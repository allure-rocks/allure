import { Controller } from "@hotwired/stimulus";
import { cssColor } from "../lib/css_color";
import { applyBasemapTheme, basemapFollowsPage, documentTheme, resolveBasemapTheme } from "../lib/basemap_theme";
import { overlayAnchorLayerId } from "../lib/map_overlay_anchor";

// Privacy-zone map picker (DESIGN.md §14.4).
//
// A hand-typed digit silently fails to mask a home address, so the zone
// editor is a map: a draggable centre marker draws a live radius circle in
// the warning colour. The numeric fields are never hidden — they are the
// accessible, keyboard-operable equivalent and remain the source of truth on
// submit. With JavaScript unavailable the map stays hidden and the numeric
// form still works and still validates.
const FRANCE_CENTER = [2.5, 46.6];
const CLOSE_ZOOM = 13;
const SEARCH_ZOOM = 16;
const FAR_ZOOM = 5;
const CIRCLE_STEPS = 64;
const EARTH_RADIUS_METERS = 6371000;

const BLANK_STYLE = { version: 8, sources: {}, layers: [] };
const CIRCLE_SOURCE = "allure-zone";
const CIRCLE_FILL = "allure-zone-fill";
const CIRCLE_LINE = "allure-zone-line";

export default class extends Controller {
  static targets = [
    "map", "latitude", "longitude", "radius", "radiusRange",
    "search", "searchInput", "searchButton", "searchResults", "searchStatus",
  ];

  static values = {
    styleUrl: String,
    styleUrlDark: String,
    unitSystem: { type: String, default: "metric" },
    locale: Object,
    searchUrl: String,
    searchMessages: Object,
    focusSearch: Boolean,
    // The account's basemap preference (DESIGN.md §15.2).
    basemapTheme: { type: String, default: "auto" },
  };

  async connect() {
    this.connected = true;
    applyBasemapTheme(this.mapTarget, this.#basemapTheme());
    this.abortController = new AbortController();
    this.searchOptions = [];
    this.searchIndex = -1;
    this.mapTarget.hidden = false;
    if (this.hasSearchTarget && this.searchUrlValue) {
      this.searchTarget.hidden = false;
      // A new zone starts by finding its place. Only with a fine pointer: on a
      // phone the focus would open the keyboard over the map.
      if (this.focusSearchValue && window.matchMedia("(pointer: fine)").matches) {
        this.searchInputTarget.focus({ preventScroll: true });
      }
    }

    const [maplibre, { default: workerUrl }] = await Promise.all([
      import("maplibre-gl"),
      import("maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url"),
    ]);
    if (!this.connected) return;
    maplibre.setWorkerUrl(workerUrl);

    const center = this.#coordinates() ?? FRANCE_CENTER;
    const style = await this.#loadStyle(this.#styleUrlForTheme(this.#basemapTheme()));
    if (!this.connected) return;

    this.maplibre = maplibre;
    this.map = new maplibre.Map({
      container: this.mapTarget,
      style,
      center,
      zoom: this.#coordinates() ? CLOSE_ZOOM : FAR_ZOOM,
      locale: this.localeValue,
    });
    this.currentStyleUrl = this.#styleUrlForTheme(this.#basemapTheme());

    const markerElement = document.createElement("div");
    markerElement.className = "allure-map-marker allure-map-marker--zone";
    this.marker = new maplibre.Marker({ element: markerElement, draggable: true })
      .setLngLat(center)
      .addTo(this.map);
    this.marker.on("dragend", () => this.#markerMoved());

    this.map.on("style.load", () => {
      if (this.connected) this.#drawCircle();
    });
    if (this.#styleParsed()) this.#drawCircle();

    const { NavigationControl, FullscreenControl, ScaleControl } = maplibre;
    this.map.addControl(new NavigationControl({ visualizePitch: true }), "top-right");
    this.map.addControl(new FullscreenControl(), "top-right");
    this.map.addControl(
      new ScaleControl({ unit: this.unitSystemValue === "imperial" ? "imperial" : "metric" }),
      "bottom-left"
    );
  }

  disconnect() {
    this.connected = false;
    this.abortController?.abort();
    this.searchAbortController?.abort();
    this.searchAbortController = null;
    this.marker?.remove();
    this.map?.remove();
    this.marker = null;
    this.map = null;
    this.maplibre = null;
    this.abortController = null;
    this.currentStyleUrl = null;
  }

  // A forced basemap ignores the page theme.
  themeChanged(event) {
    if (!basemapFollowsPage(this.basemapThemeValue)) return;

    const theme = resolveBasemapTheme(this.basemapThemeValue, event.detail?.theme);
    applyBasemapTheme(this.mapTarget, theme);
    this.#applyTheme(theme);
  }

  // Numeric fields are the source of truth: editing them moves the marker.
  coordinatesChanged() {
    const coordinates = this.#coordinates();
    if (!coordinates || !this.marker) return;
    this.marker.setLngLat(coordinates);
    this.map?.flyTo({ center: coordinates, animate: false });
    this.#drawCircle();
  }

  radiusFromNumber() {
    const radius = this.#radius();
    if (radius === null) return;
    if (this.hasRadiusRangeTarget) this.radiusRangeTarget.value = String(radius);
    this.#drawCircle();
  }

  radiusFromSlider() {
    if (!this.hasRadiusTarget || !this.hasRadiusRangeTarget) return;
    this.radiusTarget.value = this.radiusRangeTarget.value;
    this.#drawCircle();
  }

  // Place search (DESIGN.md §14.4): one request per explicit search — Enter
  // or the button, never per keystroke, as the public Nominatim usage policy
  // requires. The query goes to the instance, which asks its own provider.
  searchKeydown(event) {
    switch (event.key) {
      case "Enter":
        // The field sits inside the zone form: Enter must not submit it.
        event.preventDefault();
        if (this.searchIndex >= 0) this.#selectResult(this.searchIndex);
        else this.search();
        break;
      case "ArrowDown":
        event.preventDefault();
        this.#moveResult(1);
        break;
      case "ArrowUp":
        event.preventDefault();
        this.#moveResult(-1);
        break;
      case "Escape":
        if (!this.searchResultsTarget.hidden) {
          event.preventDefault();
          this.#closeResults();
        }
        break;
    }
  }

  async search() {
    if (!this.hasSearchInputTarget || !this.searchUrlValue) return;
    const query = this.searchInputTarget.value.trim();
    if (query.length < 3) {
      this.#closeResults();
      this.#searchStatus("too_short");
      return;
    }

    this.searchAbortController?.abort();
    const controller = new AbortController();
    this.searchAbortController = controller;
    this.#searchBusy(true);
    this.#searchStatus("searching");

    const url = new URL(this.searchUrlValue, window.location.origin);
    url.searchParams.set("privacy_zone_query", query);

    try {
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: controller.signal,
      });
      if (!this.connected || this.searchAbortController !== controller) return;
      if (!response.ok) throw new Error(`Search failed with ${response.status}`);
      const data = await response.json();
      if (!this.connected || this.searchAbortController !== controller) return;
      this.#renderResults(Array.isArray(data.results) ? data.results : []);
    } catch (error) {
      if (error.name === "AbortError" || !this.connected) return;
      this.#closeResults();
      this.#searchStatus("unavailable");
    } finally {
      if (this.searchAbortController === controller) this.#searchBusy(false);
    }
  }

  closeSearchResults() {
    this.#closeResults();
  }

  #renderResults(results) {
    this.searchOptions = results.filter((result) =>
      typeof result?.label === "string" &&
      Number.isFinite(result.latitude) && Number.isFinite(result.longitude));
    this.searchIndex = -1;
    this.searchResultsTarget.replaceChildren();

    if (this.searchOptions.length === 0) {
      this.#closeResults();
      this.#searchStatus("empty");
      return;
    }

    this.#searchStatus(null);
    this.searchOptions.forEach((result, index) => {
      const option = document.createElement("li");
      option.className = "dropdown-item text-wrap";
      option.id = `privacy-zone-search-${index}`;
      option.setAttribute("role", "option");
      option.setAttribute("aria-selected", "false");
      option.textContent = result.label;
      option.addEventListener("mousedown", (event) => {
        event.preventDefault();
        this.#selectResult(index);
      });
      this.searchResultsTarget.append(option);
    });
    this.searchResultsTarget.hidden = false;
    this.searchInputTarget.setAttribute("aria-expanded", "true");
  }

  #moveResult(delta) {
    const count = this.searchOptions.length;
    if (count === 0 || this.searchResultsTarget.hidden) return;
    this.searchIndex = (this.searchIndex + delta + count) % count;
    Array.from(this.searchResultsTarget.children).forEach((child, index) => {
      const active = index === this.searchIndex;
      child.classList.toggle("active", active);
      child.setAttribute("aria-selected", active ? "true" : "false");
    });
    this.searchInputTarget.setAttribute("aria-activedescendant", `privacy-zone-search-${this.searchIndex}`);
  }

  #selectResult(index) {
    const result = this.searchOptions[index];
    if (!result) return;

    if (this.hasLatitudeTarget) this.latitudeTarget.value = result.latitude.toFixed(5);
    if (this.hasLongitudeTarget) this.longitudeTarget.value = result.longitude.toFixed(5);
    this.searchInputTarget.value = result.label;
    this.#closeResults();
    this.#searchStatus("selected", result.label);

    const coordinates = this.#coordinates();
    if (!coordinates) return;
    this.marker?.setLngLat(coordinates);
    this.map?.jumpTo({ center: coordinates, zoom: SEARCH_ZOOM });
    this.#drawCircle();
  }

  #closeResults() {
    if (!this.hasSearchResultsTarget) return;
    this.searchResultsTarget.hidden = true;
    this.searchIndex = -1;
    this.searchInputTarget.setAttribute("aria-expanded", "false");
    this.searchInputTarget.removeAttribute("aria-activedescendant");
  }

  #searchBusy(busy) {
    if (!this.hasSearchButtonTarget) return;
    this.searchButtonTarget.disabled = busy;
    this.searchButtonTarget.classList.toggle("btn-loading", busy);
  }

  #searchStatus(key, label = "") {
    if (!this.hasSearchStatusTarget) return;
    const message = key ? (this.searchMessagesValue[key] ?? "") : "";
    this.searchStatusTarget.textContent = message.replace("%{label}", () => label);
  }

  #markerMoved() {
    if (!this.marker) return;
    const { lng, lat } = this.marker.getLngLat();
    if (this.hasLatitudeTarget) this.latitudeTarget.value = lat.toFixed(5);
    if (this.hasLongitudeTarget) this.longitudeTarget.value = lng.toFixed(5);
    this.#drawCircle();
  }

  #coordinates() {
    if (!this.hasLatitudeTarget || !this.hasLongitudeTarget) return null;
    const latitude = Number.parseFloat(this.latitudeTarget.value);
    const longitude = Number.parseFloat(this.longitudeTarget.value);
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return null;
    return [longitude, latitude];
  }

  #radius() {
    if (!this.hasRadiusTarget) return null;
    const radius = Number.parseInt(this.radiusTarget.value, 10);
    if (!Number.isFinite(radius) || radius < 1 || radius > 10000) return null;
    return radius;
  }

  #drawCircle() {
    if (!this.map || !this.#styleParsed()) return;
    const center = this.#coordinates();
    const radius = this.#radius();
    const data = center && radius
      ? { type: "Feature", geometry: { type: "Polygon", coordinates: [this.#circle(center, radius)] }, properties: {} }
      : { type: "FeatureCollection", features: [] };

    if (!this.map.getSource(CIRCLE_SOURCE)) {
      // Above the basemap geometry, under its trailing labels (map_overlay_anchor).
      const anchor = overlayAnchorLayerId(this.map.getStyle().layers);
      this.map.addSource(CIRCLE_SOURCE, { type: "geojson", data });
      this.map.addLayer({
        id: CIRCLE_FILL,
        type: "fill",
        source: CIRCLE_SOURCE,
        paint: { "fill-color": this.#warningColor(), "fill-opacity": 0.2 },
      }, anchor);
      this.map.addLayer({
        id: CIRCLE_LINE,
        type: "line",
        source: CIRCLE_SOURCE,
        paint: { "line-color": this.#warningColor(), "line-width": 2 },
      }, anchor);
    } else {
      this.map.getSource(CIRCLE_SOURCE).setData(data);
    }
  }

  #circle([longitude, latitude], radius) {
    const angular = radius / EARTH_RADIUS_METERS;
    const latRad = (latitude * Math.PI) / 180;
    const ring = [];
    for (let step = 0; step <= CIRCLE_STEPS; step += 1) {
      const bearing = (step * 2 * Math.PI) / CIRCLE_STEPS;
      const lat = Math.asin(
        Math.sin(latRad) * Math.cos(angular) +
        Math.cos(latRad) * Math.sin(angular) * Math.cos(bearing)
      );
      const lng = ((longitude * Math.PI) / 180) + Math.atan2(
        Math.sin(bearing) * Math.sin(angular) * Math.cos(latRad),
        Math.cos(angular) - Math.sin(latRad) * Math.sin(lat)
      );
      ring.push([(lng * 180) / Math.PI, (lat * 180) / Math.PI]);
    }
    return ring;
  }

  #warningColor() {
    return cssColor("--warning", "#f59f00");
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
        const ours = [CIRCLE_FILL, CIRCLE_LINE]
          .map((id) => previous.layers.find((layer) => layer.id === id))
          .filter(Boolean);
        const anchorId = overlayAnchorLayerId(layers);
        const anchor = anchorId === undefined ? -1 : layers.findIndex((layer) => layer.id === anchorId);
        layers.splice(anchor === -1 ? layers.length : anchor, 0, ...ours);
        const sources = { ...next.sources };
        if (previous.sources[CIRCLE_SOURCE]) sources[CIRCLE_SOURCE] = previous.sources[CIRCLE_SOURCE];
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
