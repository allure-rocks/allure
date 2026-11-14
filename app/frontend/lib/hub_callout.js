// The selection callout of the hub charts (DESIGN.md §15.1, §15.3): a small
// framed panel floating over the card, pointing at the selected week or day,
// so selecting never pushes the page down. Placed above its anchor when the
// card has the room, below it otherwise, and clamped inside the card
// horizontally; the arrow keeps pointing at the anchor.
const GAP = 8
const MARGIN = 8
const ARROW_INSET = 14

// `anchor` is a viewport rect-like `{ x, top, bottom }`; `limit` is the
// element whose box the callout must stay within (the card).
export function placeCallout(callout, anchor, limit) {
  const parent = callout.offsetParent
  if (!parent) return

  const parentBox = parent.getBoundingClientRect()
  const limitBox = (limit || parent).getBoundingClientRect()
  const width = callout.offsetWidth
  const height = callout.offsetHeight

  const minLeft = limitBox.left + MARGIN
  const maxLeft = limitBox.right - MARGIN - width
  const left = Math.max(minLeft, Math.min(anchor.x - width / 2, maxLeft))

  const below = anchor.top - GAP - height < limitBox.top + MARGIN
  const top = below ? anchor.bottom + GAP : anchor.top - GAP - height

  callout.style.left = `${left - parentBox.left}px`
  callout.style.top = `${top - parentBox.top}px`
  const arrow = Math.max(ARROW_INSET, Math.min(anchor.x - left, width - ARROW_INSET))
  callout.style.setProperty("--hub-callout-arrow", `${arrow}px`)
  callout.classList.toggle("hub-callout--below", below)
}

// Closes the callout on a press outside `root` (the controller's element):
// selecting elsewhere on the page dismisses it like a popover. Returns the
// teardown function.
export function dismissOnOutsidePress(root, onDismiss) {
  const handler = (event) => {
    if (!root.contains(event.target)) onDismiss()
  }
  document.addEventListener("pointerdown", handler)
  return () => document.removeEventListener("pointerdown", handler)
}
