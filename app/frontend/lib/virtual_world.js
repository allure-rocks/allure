// A virtual world's own map image (PLAN_VIRTUAL.md): one background layer in
// the world's colour and one image layer stretched over the world's rectangle.
// Shared by the interactive map and the static route renderer so the two can
// never draw a different world.
export const WORLD_SOURCE_ID = "allure-world";
export const WORLD_BACKGROUND_LAYER_ID = "allure-world-background";
export const WORLD_LAYER_ID = "allure-world-image";

// The dark render dims the same image, the way the raster basemap is never
// composited into a dark route image (DESIGN.md §15.4). Every property is
// always written: a theme swap back to light must reset the dark values, not
// merely stop applying them.
export function worldPaint(theme) {
  const dark = theme === "dark";
  return {
    "raster-fade-duration": 0,
    "raster-brightness-max": dark ? 0.5 : 1,
    "raster-saturation": dark ? -0.3 : 0,
    "raster-contrast": dark ? 0.1 : 0,
  };
}

// The colour around the world image. The image is dimmed by `worldPaint`; the
// background layer must be dimmed too, or the world's bright sea colour shows
// as a halo in dark mode. `darkBackground` is the server's dimmed world colour
// (Allure::Virtual::Basemap#dark_background); older payloads fall back to the
// light one.
export function worldBackground(world, theme) {
  return theme === "dark" ? (world.darkBackground ?? world.background) : world.background;
}

// MapLibre's image source takes top-left, top-right, bottom-right, bottom-left.
export function worldStyle(world, theme) {
  return {
    version: 8,
    sources: {
      [WORLD_SOURCE_ID]: {
        type: "image",
        url: world.image,
        coordinates: world.coordinates,
      },
    },
    layers: [
      {
        id: WORLD_BACKGROUND_LAYER_ID,
        type: "background",
        paint: { "background-color": worldBackground(world, theme) },
      },
      {
        id: WORLD_LAYER_ID,
        type: "raster",
        source: WORLD_SOURCE_ID,
        paint: worldPaint(theme),
      },
    ],
  };
}
