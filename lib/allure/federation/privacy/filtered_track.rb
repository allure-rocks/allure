# frozen_string_literal: true

module Allure
  module Federation
    module Privacy
      FilteredTrack = Data.define(
        :segments,
        :visible_points_count,
        :points_removed,
        :interior_points_removed,
        :bounds,
        :usable
      ) do
        def initialize(segments:, visible_points_count:, points_removed:, interior_points_removed: false, bounds:, usable:)
          frozen_segments = segments.map do |segment|
            segment.map { |point| point.freeze }.freeze
          end.freeze
          frozen_bounds = bounds&.freeze

          super(
            segments: frozen_segments,
            visible_points_count:,
            points_removed:,
            interior_points_removed:,
            bounds: frozen_bounds,
            usable:
          )
        end

        def visible_point_count = visible_points_count
        def points_removed? = points_removed
        def interior_points_removed? = interior_points_removed
        def removed_points? = points_removed
        def usable? = usable
        def has_usable_segment? = usable
      end
    end
  end
end
