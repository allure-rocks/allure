# frozen_string_literal: true

module Allure
  module Gpx
    # No `<trkseg>` with at least two points survived parsing.
    class NoTrackError < Error; end
  end
end
