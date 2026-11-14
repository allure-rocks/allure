// Pure geometry for the avatar crop stage (DESIGN.md §9.4). The stage shows a
// square window over the picked image and the account moves and zooms the
// image under it. Every value is in source pixels of the oriented image — the
// space the browser measures and the server crops in — except the stage size,
// which is CSS pixels.

const MIN_CROP_PIXELS = 128
const MAX_ZOOM_DIVISOR = 16

export function clamp(value, min, max) {
  if (max < min) return min
  return Math.min(Math.max(value, min), max)
}

// The side of the kept square at a zoom level: the short side fills the
// window at 1, and each further level keeps 1/zoom of it.
export function cropSide({ width, height, zoom }) {
  return Math.min(width, height) / Math.max(1, zoom)
}

// How far the account may zoom in before the square gets too small to feed
// the 512 px avatar.
export function maxZoom({ width, height }) {
  const smallest = Math.max(MIN_CROP_PIXELS, Math.min(width, height) / MAX_ZOOM_DIVISOR)
  return Math.max(1, Math.min(width, height) / smallest)
}

// The square the account keeps: `side` source pixels around the centre,
// clamped so it never leaves the image.
export function cropRect({ width, height, zoom, centreX, centreY }) {
  const side = cropSide({ width, height, zoom })
  return {
    left: clamp(centreX - side / 2, 0, width - side),
    top: clamp(centreY - side / 2, 0, height - side),
    side
  }
}

// Where the image sits in a square stage of `stageSize` CSS pixels.
export function layout({ width, height, zoom, centreX, centreY, stageSize }) {
  const rect = cropRect({ width, height, zoom, centreX, centreY })
  const scale = stageSize / rect.side
  return {
    rect,
    scale,
    width: width * scale,
    height: height * scale,
    left: -rect.left * scale,
    top: -rect.top * scale
  }
}

// Drags the image by (dx, dy) CSS pixels: the window moves the other way.
export function panBy({ width, height, zoom, centreX, centreY, dx, dy, stageSize }) {
  const rect = cropRect({ width, height, zoom, centreX, centreY })
  const scale = stageSize / rect.side
  return centred({
    width, height, zoom,
    centreX: centreX - dx / scale,
    centreY: centreY - dy / scale
  })
}

// Zooms while keeping the source point under (anchorX, anchorY) — stage CSS
// pixels from its top-left corner — where it is.
export function zoomAround({ width, height, zoom, centreX, centreY, nextZoom, anchorX, anchorY, stageSize }) {
  const rect = cropRect({ width, height, zoom, centreX, centreY })
  const scale = stageSize / rect.side
  const sourceX = rect.left + anchorX / scale
  const sourceY = rect.top + anchorY / scale
  const clamped = clamp(nextZoom, 1, maxZoom({ width, height }))
  const side = cropSide({ width, height, zoom: clamped })
  return centred({
    width, height, zoom: clamped,
    centreX: sourceX - (anchorX / stageSize) * side + side / 2,
    centreY: sourceY - (anchorY / stageSize) * side + side / 2
  })
}

// Clamps a centre so the square stays inside the image.
export function centred({ width, height, zoom, centreX, centreY }) {
  const side = cropSide({ width, height, zoom })
  return {
    zoom,
    centreX: clamp(centreX, side / 2, width - side / 2),
    centreY: clamp(centreY, side / 2, height - side / 2)
  }
}

// The square as the form sends it: whole pixels of the oriented image.
export function placement({ left, top, side }) {
  return { x: Math.round(left), y: Math.round(top), size: Math.max(1, Math.round(side)) }
}
