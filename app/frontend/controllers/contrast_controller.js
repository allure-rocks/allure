import { Controller } from "@hotwired/stimulus";
import { cssColor } from "../lib/css_color";

// Live WCAG contrast ratios (DESIGN.md §22). Palette-vs-white ratios print
// server-side (Allure::Contrast, spec-backed); surface ratios depend on
// resolved theme variables, so they compute here and recompute on
// allure:theme-changed. The math mirrors Allure::Contrast.ratio; keep both in
// sync. No twin in lib/ is possible — the surface inputs only exist as
// computed CSS values.
export default class extends Controller {
  static targets = ["swatch", "ratio"];

  connect() {
    this.boundRefresh = () => this.refresh();
    window.addEventListener("allure:theme-changed", this.boundRefresh);
    this.refresh();
  }

  disconnect() {
    window.removeEventListener("allure:theme-changed", this.boundRefresh);
  }

  refresh() {
    const surface = cssColor("--allure-surface-raised", "#ffffff");
    this.swatchTargets.forEach((swatch, index) => {
      const target = this.ratioTargets[index];
      if (target) target.textContent = ratio(swatch.dataset.contrastColor, surface).toFixed(2);
    });
  }
}

function ratio(first, second) {
  const [lighter, darker] = [luminance(first), luminance(second)].sort((a, b) => b - a);
  return (lighter + 0.05) / (darker + 0.05);
}

function luminance(color) {
  const [r, g, b] = parse(color).map((channel) => {
    const c = channel / 255;
    return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function parse(color) {
  const hex = color.trim().toLowerCase();
  if (hex.startsWith("#")) {
    const full = hex.length === 4 ? `#${[...hex.slice(1)].map((c) => c + c).join("")}` : hex;
    return [1, 3, 5].map((i) => parseInt(full.slice(i, i + 2), 16));
  }
  const match = hex.match(/rgba?\(([^)]+)\)/);
  if (match) return match[1].split(",").slice(0, 3).map((n) => Number(n.trim()));
  return [0, 0, 0];
}
