# frozen_string_literal: true

module Allure
  module Gpx
    # A point's coordinate, elevation, or timestamp text could not be parsed
    # as a finite number/time, or a coordinate was outside its valid range.
    class InvalidPointError < Error; end
  end
end
