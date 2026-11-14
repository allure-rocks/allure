# Zwift world map images

One image per Zwift world, drawn under a virtual activity's track instead of
the ordinary basemap (`PLAN_VIRTUAL.md` §2.1).

## They are not committed

The images are Zwift's own world maps, and Zwift's artwork is not ours to
redistribute under the AGPL. No `.webp` file lives in this repository or in the
published image: the directory only carries this note. An operator who wants
the world maps generates them locally with `bin/rails virtual:world_images`,
and a checkout without them draws the ordinary basemap instead — the map, the
owner route images and the publication route images all fall back the same way.

## Provenance

The images are taken from Zwift's map CDN (`cdn.zwift.com/static/images/maps/`),
the files the MIT-licensed
[`andipaetzold/zwift-data`](https://github.com/andipaetzold/zwift-data) package
names for each world. The map credit is `© Zwift`.

They are converted, not redrawn: turned north-up where Zwift stores the artwork
with north to the right, resized so the longest side is 4096 px, and encoded as
WebP (quality 82) by `bin/rails virtual:world_images`. Nothing else about the
artwork changes.

Each file is named after the SHA-256 of its source (`<world>-<first 8 hex>.webp`),
so a new map always takes a new URL and no browser keeps the old one behind the
production cache headers.

| World | CDN file | Rotated | Changed |
|---|---|---|---|
| Watopia | `MiniMap_Watopia_2.png` | | October 2026: north-west archipelago |
| Richmond | `MiniMap_Richmond.png` | | |
| London | `MiniMap_London.png` | | |
| New York | `MiniMap_NewYork_2.png` | | |
| Innsbruck | `MiniMap_Innsbruck.png` | | |
| Bologna | `MiniMap_Bologna.png` | | |
| Yorkshire | `MiniMap_Yorkshire.png` | | |
| Crit City | `MiniMap_CritCity.png` | | |
| Makuri Islands | `MiniMap_Japan.png` | quarter turn | |
| France | `MiniMap_France.png` | quarter turn | |
| Paris | `MiniMap_Paris_2.png` | quarter turn | July 2026: Montmartre expansion |
| Scotland | `MiniMap_Scotland.png` | quarter turn | |

The rectangles each image is drawn into are the `bounds` of the MIT-licensed
`andipaetzold/zwift-data` package (`src/worlds.ts`), and live in
`lib/allure/virtual/platforms.rb` beside the venue they belong to. Paris is the
exception: its July 2026 map has no published rectangle yet, so the rectangle is
the previous one shifted by a quarter of its size north and east, where the two
maps register exactly (same scale, a 1024 px translation of the 4096 px frame).

## Generating them

```sh
bin/rails virtual:world_images
bin/rails virtual:world_images WORLD=paris
```

The task downloads the pinned sources, refuses to write anything when a source
no longer matches its pinned digest, and rewrites the files here. They are
ignored by Git (`.gitignore`). It is an operator task: the application never
downloads an image at runtime.

To carry the images into a production image, generate them in the checkout
before building it. The public release image is built from a clean checkout and
therefore ships without them.

When Zwift changes a map, the task fails and prints the new digest. Review the
new artwork (the world's rectangle and its rotation), update the digest in the
task and the image name in the catalogue, run the task, then re-render the owner
route images drawn on that world — a one-off migration, as
`20261107120000_rerender_virtual_world_route_images` did for Watopia and Paris.
