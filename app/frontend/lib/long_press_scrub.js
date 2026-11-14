// Long-press scrubbing for touch charts (DESIGN.md §15.1, §18.4). A finger
// held still for LONG_PRESS_DELAY enters scrub mode: sliding then moves the
// selection under the finger instead of scrolling, and lifting keeps it. A
// finger that moves first is a scroll and stays the browser's. Mouse and pen
// never scrub; they click. The caller owns the selection, this only reports
// finger positions, and must call `destroy()` on disconnect.
//
// A chart re-rendering under the finger (a cursor update redraws part of the
// SVG) can detach the node the touch started on, and the browser keeps
// sending that touch's events to the detached node, where they no longer
// bubble. The handlers therefore also listen on the touch's own target, and
// each event is handled once whichever path delivers it.
const LONG_PRESS_DELAY = 400
const MOVE_TOLERANCE = 10
// The click a browser may still synthesize after the finger lifts.
const CLICK_GUARD = 500

export class LongPressScrub {
  constructor(element, { onStart, onMove, onEnd } = {}) {
    this.element = element
    this.onStart = onStart
    this.onMove = onMove
    this.onEnd = onEnd
    this.timer = null
    this.origin = null
    this.scrubbing = false
    this.guardUntil = 0
    this.touchTarget = null
    this.handled = new WeakSet()

    this.handleStart = (event) => this.#start(event)
    this.handleMove = (event) => this.#once(event, () => this.#move(event))
    this.handleEnd = (event) => this.#once(event, () => this.#end(event))
    this.handleCancel = (event) => this.#once(event, () => this.#cancel())
    this.handleContextMenu = (event) => {
      if (this.scrubbing || this.timer) event.preventDefault()
    }

    element.addEventListener("touchstart", this.handleStart, { passive: true })
    // Not passive: once scrubbing, the slide must not scroll the page.
    element.addEventListener("touchmove", this.handleMove, { passive: false })
    element.addEventListener("touchend", this.handleEnd)
    element.addEventListener("touchcancel", this.handleCancel)
    element.addEventListener("contextmenu", this.handleContextMenu)
  }

  get active() {
    return this.scrubbing
  }

  // True once for the click that follows a scrub, so the caller ignores it.
  consumeClick() {
    if (Date.now() > this.guardUntil) return false

    this.guardUntil = 0
    return true
  }

  destroy() {
    this.#clearTimer()
    this.#releaseTarget()
    this.element.removeEventListener("touchstart", this.handleStart)
    this.element.removeEventListener("touchmove", this.handleMove)
    this.element.removeEventListener("touchend", this.handleEnd)
    this.element.removeEventListener("touchcancel", this.handleCancel)
    this.element.removeEventListener("contextmenu", this.handleContextMenu)
  }

  #once(event, handler) {
    if (this.handled.has(event)) return

    this.handled.add(event)
    handler()
  }

  #holdTarget(target) {
    this.#releaseTarget()
    if (!target || target === this.element) return

    this.touchTarget = target
    target.addEventListener("touchmove", this.handleMove, { passive: false })
    target.addEventListener("touchend", this.handleEnd)
    target.addEventListener("touchcancel", this.handleCancel)
  }

  #releaseTarget() {
    if (!this.touchTarget) return

    this.touchTarget.removeEventListener("touchmove", this.handleMove)
    this.touchTarget.removeEventListener("touchend", this.handleEnd)
    this.touchTarget.removeEventListener("touchcancel", this.handleCancel)
    this.touchTarget = null
  }

  #start(event) {
    if (event.touches.length !== 1) return this.#cancel()

    const touch = event.touches[0]
    this.#holdTarget(event.target)
    this.origin = { x: touch.clientX, y: touch.clientY }
    this.#clearTimer()
    this.timer = setTimeout(() => {
      this.timer = null
      this.scrubbing = true
      try { navigator.vibrate?.(8) } catch { /* unsupported */ }
      this.onStart?.(this.origin.x, this.origin.y)
    }, LONG_PRESS_DELAY)
  }

  #move(event) {
    const touch = event.touches[0]
    if (!touch) return

    if (this.scrubbing) {
      if (event.cancelable) event.preventDefault()
      this.onMove?.(touch.clientX, touch.clientY)
      return
    }
    if (!this.timer || !this.origin) return

    const dx = touch.clientX - this.origin.x
    const dy = touch.clientY - this.origin.y
    if (Math.hypot(dx, dy) > MOVE_TOLERANCE) this.#clearTimer()
  }

  #end(event) {
    this.#clearTimer()
    this.#releaseTarget()
    if (!this.scrubbing) return

    // Suppress the synthesized mouse events and click of the long press.
    if (event.cancelable) event.preventDefault()
    this.guardUntil = Date.now() + CLICK_GUARD
    this.scrubbing = false
    this.onEnd?.()
  }

  #cancel() {
    this.#clearTimer()
    this.#releaseTarget()
    if (!this.scrubbing) return

    this.scrubbing = false
    this.onEnd?.()
  }

  #clearTimer() {
    clearTimeout(this.timer)
    this.timer = null
  }
}
