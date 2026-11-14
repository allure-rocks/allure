# frozen_string_literal: true

module Allure
  module Gpx
    # The document is well-formed XML but is not a supported GPX file: wrong
    # root element, unsupported namespace, or unsupported version attribute.
    class UnsupportedGpxError < Error; end
  end
end
