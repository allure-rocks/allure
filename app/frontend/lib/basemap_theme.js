// The basemap variant of every interactive map (DESIGN.md §15.2). The account
// preference `route_image_theme` (« Cartes et images des parcours ») governs
// both the generated route images and the live basemap: `auto` follows the
// page theme, `light` and `dark` force one variant whatever the page theme.
//
// The map element carries its own `data-bs-theme`, so every Tabler token read
// inside it — controls, markers, popups, the grid behind a tile-less map, the
// arrow halo — follows the basemap rather than the page.
export const BASEMAP_PREFERENCES = Object.freeze([ "auto", "light", "dark" ]);

export function resolveBasemapTheme(preference, documentTheme) {
  if (preference === "light" || preference === "dark") return preference;
  return documentTheme === "dark" ? "dark" : "light";
}

export function basemapFollowsPage(preference) {
  return preference !== "light" && preference !== "dark";
}

export function applyBasemapTheme(element, theme) {
  if (element && element.getAttribute("data-bs-theme") !== theme) {
    element.setAttribute("data-bs-theme", theme);
  }
}

export function documentTheme() {
  return typeof document === "undefined" ? undefined : document.documentElement.dataset.bsTheme;
}
