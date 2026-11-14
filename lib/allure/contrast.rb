# frozen_string_literal: true

module Allure
  # WCAG 2.1 contrast ratio between two sRGB hex colours. Pure math, no
  # framework: (L1 + 0.05) / (L2 + 0.05) with relative luminance per
  # https://www.w3.org/TR/WCAG21/#dfn-relative-luminance
  #
  # Used to prove the generated-avatar palette claim (white text >= 4.5:1 on
  # every entry) in CI. Ratios against theme surfaces cannot be computed here
  # — Tabler variables resolve client-side — so the styleguide pairs these
  # server-side white ratios with live surface ratios from
  # contrast_controller.js, which mirrors this math.
  module Contrast
    def self.ratio(first, second)
      lighter, darker = [ relative_luminance(first), relative_luminance(second) ].sort.reverse
      (lighter + 0.05) / (darker + 0.05)
    end

    def self.relative_luminance(hex)
      red, green, blue = hex.delete_prefix("#").scan(/../).map { it.hex / 255.0 }
      (0.2126 * linear(red)) + (0.7152 * linear(green)) + (0.0722 * linear(blue))
    end
    private_class_method :relative_luminance

    def self.linear(channel)
      if channel <= 0.04045
        channel / 12.92
      else
        ((channel + 0.055) / 1.055)**2.4
      end
    end
    private_class_method :linear
  end
end
