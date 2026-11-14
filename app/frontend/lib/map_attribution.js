// MapLibre opens the compact attribution on creation, and again whenever the
// style or a source updates its attribution text or the map resizes.
// Collapse it and keep re-collapsing until the reader opens it themselves;
// after that the native toggle owns the state. The attribution itself always
// comes from the style document: the basemap licence requires it.
export function collapseAttribution(map, container) {
  const element = container?.querySelector(".maplibregl-ctrl-attrib");
  if (!map || !element) return;

  const collapse = () => {
    element.classList.remove("maplibregl-compact-show");
    element.removeAttribute("open");
  };

  collapse();
  const events = [ "resize", "styledata", "sourcedata" ];
  events.forEach((event) => map.on(event, collapse));
  element.querySelector("summary")?.addEventListener(
    "click",
    () => events.forEach((event) => map.off(event, collapse)),
    { once: true },
  );
}
