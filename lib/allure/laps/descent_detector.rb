# frozen_string_literal: true

module Allure
  module Laps
    # Mirrors the climb detector on the inverted elevation profile: the
    # segmenter's peak is the real bottom and its gain is the real loss. The
    # stored grade stays positive; the source carries the direction.
    class DescentDetector < ElevationDetector
      private

      def source = "descent"

      def transformed(profile)
        profile.map { |point| point.merge(elevation: -point.fetch(:elevation)) }
      end
    end
  end
end
