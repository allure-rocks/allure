# frozen_string_literal: true

module Allure
  module Federation
    module Privacy
      class SanitizedTrackSerializer
        class Unavailable < StandardError; end

        def initialize(filtered:)
          @filtered = filtered
        end

        def call
          raise Unavailable, "sanitized route is unavailable" unless @filtered.usable?

          {
            type: "FeatureCollection",
            features: @filtered.segments.each_with_index.map do |coordinates, segment_index|
              {
                type: "Feature",
                geometry: { type: "LineString", coordinates: },
                properties: { segment_index: }
              }
            end
          }
        end
      end
    end
  end
end
