# frozen_string_literal: true

module Allure
  module Gpx
    # Timestamps decreased within a segment, or between two segments in
    # document order.
    class NonMonotonicTimestampError < Error; end
  end
end
