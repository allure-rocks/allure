import { Controller } from "@hotwired/stimulus"

const COUNT = 5
const BASES = ["max", "reserve"]

const fill = (template, values) =>
  String(template).replace(/%\{(\w+)\}/g, (match, key) => (key in values ? String(values[key]) : match))

const integerIn = (input, min, max) => {
  if (!input || input.value.trim() === "") return null
  const value = Number(input.value)
  return Number.isInteger(value) && value >= min && value <= max ? value : null
}

// The zone table of /settings/heart-rate follows the form as it is typed
// (docs/dev/HEART-RATE.md), so a change of basis or bound shows its bpm
// before it is saved. Same rule and rounding as Allure::HeartRate::Zones;
// anything the model would refuse shows dashes. Nothing is sent.
export default class extends Controller {
  static targets = ["max", "rest", "basis", "bound", "range", "floor", "empty"]
  static values = { formats: Object }

  update() {
    const zones = this.#zones()
    const formats = this.formatsValue

    this.rangeTargets.forEach((cell, index) => {
      cell.textContent = zones ? this.#range(zones.thresholds, index) : "—"
    })
    if (this.hasEmptyTarget) this.emptyTarget.hidden = Boolean(zones)
    if (this.hasFloorTarget) {
      this.floorTarget.hidden = !zones
      if (zones) {
        this.floorTarget.textContent = fill(formats.floor[zones.basis], { bpm: zones.floor, percent: zones.floorPercent })
      }
    }
  }

  #zones() {
    const max = integerIn(this.hasMaxTarget && this.maxTarget, 100, 220)
    if (max === null) return null

    const basis = BASES.includes(this.basisTarget?.value) ? this.basisTarget.value : "max"
    const rest = integerIn(this.hasRestTarget && this.restTarget, 25, 120)
    if (rest !== null && rest >= max) return null
    if (basis === "reserve" && rest === null) return null

    const bounds = this.boundTargets.map((input) => integerIn(input, 30, 99))
    if (bounds.length !== COUNT - 1 || bounds.some((bound) => bound === null)) return null
    if (bounds.some((bound, index) => index > 0 && bound <= bounds[index - 1])) return null

    const bpmAt = (percent) => Math.round(basis === "reserve" ? rest + (percent / 100) * (max - rest) : (percent / 100) * max)
    const thresholds = bounds.map(bpmAt)
    if (thresholds.some((value, index) => index > 0 && value <= thresholds[index - 1])) return null

    const floorPercent = bounds[0] - this.formatsValue.floor_offset
    return { basis, thresholds, floor: bpmAt(floorPercent), floorPercent }
  }

  #range(thresholds, index) {
    const { unit, below, above, between } = this.formatsValue
    if (index === 0) return fill(below, { bpm: thresholds[0], unit })
    if (index === COUNT - 1) return fill(above, { bpm: thresholds[COUNT - 2], unit })
    return fill(between, { lower: thresholds[index - 1], upper: thresholds[index] - 1, unit })
  }
}
