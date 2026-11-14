# frozen_string_literal: true

module Allure
  module Gpx
    # The immutable result of parsing an entire GPX document. `segments` is
    # every accepted `<trkseg>` from every `<trk>` element, flattened and kept
    # in document order; no straight line is implied between segments or
    # between tracks. `name`/`description` are the first non-blank values
    # found across all `<trk>` elements in document order; `calories` sums
    # every track-level calorie value present. Activity signals retain raw
    # values and their locations; classification is the detector's job.
    # `laps` holds the file-recorded laps (a FIT `lap` message or a GPX
    # `<lap>` element) in document order, or an empty array when the file
    # recorded none. `source_max_speed` is the optional device summary supplied
    # by FIT/TCX and remains nil for geometry-only formats. `source_ascent` and
    # `source_descent` are the device's own elevation totals when the file
    # carries them (FIT session messages), nil otherwise. `commute_hint` is the
    # file's own statement that the activity was a commute (a FIT `commuting`
    # sub-sport); it is metadata, never an analysis input.
    #
    # A track whose file recorded no position at all (an indoor FIT/TCX
    # activity) keeps its time and sensor readings: `#positioned?` is false and
    # the analyzer measures it from the device's distance and speed instead of
    # the geometry (PLAN_NO_GPS.md).
    Track = Data.define(:creator, :name, :description, :calories, :source_max_speed,
                        :source_ascent, :source_descent, :activity_signals, :segments, :laps,
                        :commute_hint) do
      def initialize(creator: nil, name: nil, description: nil, calories: nil, source_max_speed: nil,
                     source_ascent: nil, source_descent: nil,
                     activity_signals: [], segments:, laps: [], commute_hint: false)
        super(
          creator: TextLimits.clip(creator, TextLimits::CREATOR),
          name: TextLimits.clip(name, TextLimits::NAME),
          description: TextLimits.clip(description, TextLimits::DESCRIPTION),
          calories:,
          source_max_speed:,
          source_ascent:,
          source_descent:,
          activity_signals: activity_signals.frozen? ? activity_signals : activity_signals.freeze,
          segments: segments.frozen? ? segments : segments.freeze,
          laps: laps.frozen? ? laps : laps.freeze,
          commute_hint: commute_hint ? true : false
        )
      end

      def points_count = segments.sum(&:size)

      # A track is positioned when its segments are: a positionless recording
      # is an indoor activity the device tracked without a fix
      # (PLAN_NO_GPS.md).
      def positioned? = segments.any? { |segment| segment.positioned? }

      # Moves every point time and every recorded lap start by one offset in
      # seconds, leaving positions, durations and sensor readings untouched
      # (PLAN_DEMO.md §4: a demo instance dates its seeded recordings near the
      # present instead of the day the file was recorded). The source track is
      # never mutated; a zero or nil offset returns it unchanged. The stored
      # original file always keeps its own dates.
      def shifted(seconds)
        return self if seconds.nil? || seconds.zero?

        Track.new(
          creator: creator,
          name: name,
          description: description,
          calories: calories,
          source_max_speed: source_max_speed,
          source_ascent: source_ascent,
          source_descent: source_descent,
          activity_signals: activity_signals,
          segments: segments.map do |segment|
            Segment.new(points: segment.points.map { |point| point.with(time: point.time + seconds) })
          end,
          laps: laps.map { |lap| lap.with(started_at: lap.started_at + seconds) }
        )
      end
    end
  end
end
