# frozen_string_literal: true

module Allure
  module Fit
    # Base class for every error raised while decoding a FIT file. The
    # importer rescues this hierarchy to produce a localized validation error
    # instead of a 500. Point/segment level problems reuse the shared
    # `Allure::Gpx` errors so both parsers report the same failures.
    class Error < StandardError; end
  end
end
