# frozen_string_literal: true

module Allure
  module Segments
    # A course's average grade, in percent and signed: the net elevation change
    # from its first to its last valid elevation over its distance, so a
    # descent reads negative. Without a profile, the accumulated ascent and
    # descent give the closest net change available.
    module Grade
      module_function

      def from_elevations(elevations, distance:)
        valid = elevations.select { |elevation| Allure::Gpx::Elevation.valid?(elevation) }
        return if valid.length < 2

        percent(valid.last - valid.first, distance)
      end

      # `profile` is the stored `segments.elevation_profile` (`"d"`/`"ele"`
      # entries); it falls back to the totals when it carries no elevation.
      def from_profile(profile, distance:, ascent: nil, descent: nil)
        elevations = Array(profile).filter_map do |entry|
          entry["ele"] if entry.is_a?(Hash) && entry["ele"].is_a?(Numeric)
        end
        from_elevations(elevations, distance:) || from_totals(ascent:, descent:, distance:)
      end

      def from_totals(ascent:, descent:, distance:)
        return if ascent.nil? && descent.nil?

        percent(ascent.to_f - descent.to_f, distance)
      end

      def percent(net, distance)
        return unless distance.to_f.positive?

        (net / distance.to_f * 100.0).clamp(-100.0, 100.0)
      end
    end
  end
end
