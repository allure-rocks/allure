# frozen_string_literal: true

module Allure
  module Laps
    # Finds the climbs in a workout with the shared elevation segmenter and
    # turns each one into a detected lap with grade, score, and slice metrics.
    # Sports without recorded elevation simply yield no climbs.
    class ClimbDetector < ElevationDetector
      private

      def source = "climb"
    end
  end
end
