# frozen_string_literal: true

module Allure
  module HeartRate
    # Edwards' training impulse (PLAN_HEART_RATE.md D8): minutes in each zone
    # weighted by the zone's number, with nothing under the zones' load floor
    # (Edwards counts from 50 % of the maximum). The unit is Allure's own:
    # it is not comparable with a power-based or another application's score.
    module Load
      module_function

      def edwards(histogram, zones)
        seconds = Array.new(Zones::COUNT, 0)
        Array(histogram).each_with_index do |value, index|
          next unless value.positive?

          bpm = Histogram.bpm_for(index)
          next if bpm < zones.load_floor

          seconds[zones.zone_for(bpm) - 1] += value
        end
        seconds.each_with_index.sum { |value, index| value.to_f / 60 * (index + 1) }.round(1)
      end
    end
  end
end
