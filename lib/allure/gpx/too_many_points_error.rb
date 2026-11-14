# frozen_string_literal: true

module Allure
  module Gpx
    # More `<trkpt>` elements were encountered than the configured limit.
    class TooManyPointsError < Error; end
  end
end
