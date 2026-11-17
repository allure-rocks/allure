# frozen_string_literal: true

module Workouts
  # The device's own elevation totals for a parsed track, when the file
  # carries them. Complete recorded laps win over the session summary; the
  # session is the fallback when the laps are missing or incomplete. A nil
  # result means the caller must fall back to the computed profile
  # (docs/dev/ELEVATION.md).
  module DeviceElevationTotals
    # A missing final partial lap is normal, so laps may cover slightly less
    # than the whole activity.
    MINIMUM_LAP_COVERAGE = 0.95

    module_function

    # Returns `{ ascent:, descent: }` or nil.
    #
    # `virtual:` marks a rendered world's recording. Its elevation is not a
    # barometer reading: the platform's session and lap summaries may be absent
    # or inconsistent (Zwift writes a session ascent with no descent and zero
    # lap totals), so the computed profile — the one the elevation chart draws —
    # is the truth. Returns nil so the caller falls back to it.
    def call(track:, distance:, virtual: false)
      return nil if virtual

      lap_totals(track, distance) || session_totals(track)
    end

    def session_totals(track)
      ascent = usable(track.source_ascent)
      descent = usable(track.source_descent)
      return nil unless ascent && descent

      { ascent:, descent: }
    end

    def lap_totals(track, distance)
      return nil if track.laps.empty? || !distance.to_f.positive?

      covered_distance = 0.0
      ascent = 0.0
      descent = 0.0
      track.laps.each do |lap|
        lap_ascent = usable(lap.ascent)
        lap_descent = usable(lap.descent)
        next unless lap_ascent && lap_descent

        ascent += lap_ascent
        descent += lap_descent
        covered_distance += lap.distance.to_f
      end
      return nil if covered_distance < (distance.to_f * MINIMUM_LAP_COVERAGE)

      { ascent:, descent: }
    end

    def usable(value)
      return nil unless value.is_a?(Numeric) && value.finite? && value >= 0

      value.to_f
    end
  end
end
