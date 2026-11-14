# frozen_string_literal: true

module Allure
  module HeartRate
    # Where along the route each zone was ridden (PLAN_HEART_RATE.md §3.5): per
    # zone, the distance stretches whose readings fall in it, on the workout's
    # cumulative distance (recording segments laid end to end, like
    # Segments::PointStream), so the profile and the map can shade them.
    # Display only: same-zone stretches closer than MERGE_GAP are joined and
    # what remains under MIN_LENGTH is dropped, so a heart rate wavering on a
    # threshold does not shred the map. The zone times never come from here.
    module ZoneRanges
      MERGE_GAP = 50.0
      MIN_LENGTH = 20.0

      module_function

      # `{ 1 => [[start, end], …], …, 5 => […] }`, metres, rounded to 0.1.
      def compute(segments, zones)
        ranges = (1..Zones::COUNT).to_h { [ it, [] ] }
        offset = 0.0

        Array(segments).each do |segment|
          runs = {}
          Array(segment.points).each_cons(2) do |point, following|
            bpm = bpm_of(point)
            next unless bpm

            start = distance_of(point)
            finish = distance_of(following)
            next unless start && finish && finish > start

            zone = zones.zone_for(bpm)
            from = offset + start
            to = offset + finish
            last = runs[zone]
            if last && from - last[1] <= MERGE_GAP
              last[1] = to
            else
              ranges[zone] << (runs[zone] = [ from, to ])
            end
          end
          offset += segment.distance.to_f
        end

        ranges.transform_values do |list|
          list.select { |from, to| to - from >= MIN_LENGTH }.map { |from, to| [ from.round(1), to.round(1) ] }
        end
      end

      def bpm_of(point)
        value = point[Allure::Gpx::PointSerializer::KEY_HEART_RATE]
        return nil unless value.is_a?(Numeric) && value.finite?

        bpm = value.round
        Histogram::RANGE.cover?(bpm) ? bpm : nil
      end

      def distance_of(point)
        value = point[Allure::Gpx::PointSerializer::KEY_DISTANCE]
        value.to_f if value.is_a?(Numeric)
      end

      private_class_method :bpm_of, :distance_of
    end
  end
end
