# frozen_string_literal: true

module Allure
  module Gpx
    # One immutable recorded lap. A lap is whatever the source file recorded as
    # a lap boundary (a FIT `lap` message or a GPX `<lap>` element), kept in
    # document order and numbered from one. Laps are derived and display-only:
    # they are never URL-addressable and have no ShortUUID.
    #
    # Times are seconds and distances metres (SI), matching the `laps` table.
    # `moving_time` never exceeds `elapsed_time`. Metric fields the source does
    # not record are nil rather than fabricated.
    Lap = Data.define(
      :number, :started_at, :elapsed_time, :moving_time,
      :distance, :ascent, :descent, :average_speed, :max_speed, :average_pace,
      :average_heart_rate, :max_heart_rate, :average_cadence, :average_power, :lap_trigger
    ) do
      def initialize(number:, started_at:, elapsed_time:, moving_time:,
                     distance: nil, ascent: nil, descent: nil,
                     average_speed: nil, max_speed: nil, average_pace: nil,
                     average_heart_rate: nil, max_heart_rate: nil,
                     average_cadence: nil, average_power: nil, lap_trigger: nil)
        super(number:, started_at:, elapsed_time:, moving_time:, distance:, ascent:, descent:,
              average_speed:, max_speed:, average_pace:, average_heart_rate:, max_heart_rate:,
              average_cadence:, average_power:,
              lap_trigger: TextLimits.clip(lap_trigger, TextLimits::LAP_TRIGGER))
      end
    end
  end
end
