// Basemap styles do not reliably end with their symbol layers. OpenFreeMap
// liberty interleaves one-way arrows before every bridge and building, and dark
// puts water_name above the whole road network. Anchoring to the first symbol
// therefore buried the route under basemap geometry. Inserting before the first
// symbol that follows the last non-symbol layer keeps every geometry layer
// beneath our overlays and the trailing label run above them.
export function overlayAnchorLayerId(layers) {
  if (!Array.isArray(layers)) return undefined;

  let lastGeometryIndex = -1;
  layers.forEach((layer, index) => {
    if (layer.type !== "symbol") lastGeometryIndex = index;
  });

  return layers.slice(lastGeometryIndex + 1).find((layer) => layer.type === "symbol")?.id;
}
