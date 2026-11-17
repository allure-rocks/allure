# frozen_string_literal: true

module Allure
  module Weather
    # Where the « Météo » analysis tab marks the weather on the profile and
    # the map (docs/dev/WEATHER.md): at the start, then only where the weather
    # changes — another condition, a wind turning to another of the eight
    # compass sectors, or a temperature moved by 2 °C — at least 8 % of the
    # distance apart and six at most. A workout whose weather never changes
    # gets one marker halfway.
    #
    # `distances` maps each series row to the cumulative distance the athlete
    # had covered at that instant (`.distances`).
    class Markers
      MAX_MARKERS = 6
      MIN_SPACING = 0.08
      TEMPERATURE_STEP = 2.0
      CALM_WIND = 1.5

      Marker = Data.define(:distance, :row)

      # The cumulative distance at each row's instant, interpolated between
      # the two recorded points around it (points are time-ordered).
      def self.distances(points, rows)
        points = Array(points)
        return Array.new(rows.length) if points.empty?

        times = points.map { |point| point.time.to_f }
        rows.map do |row|
          index = times.bsearch_index { |time| time >= row.time } || (times.length - 1)
          next points[index].distance.to_f if index.zero?

          before = points[index - 1]
          after = points[index]
          span = times[index] - times[index - 1]
          fraction = span.positive? ? ((row.time - times[index - 1]) / span).clamp(0.0, 1.0) : 0.0
          before.distance + (after.distance - before.distance) * fraction
        end
      end

      def initialize(rows:, distances:, total_distance:)
        pairs = Array(rows).zip(Array(distances)).select { |row, distance| row.usable? && !distance.nil? }
        @candidates = pairs.map { |row, distance| Marker.new(distance:, row:) }
        @total = total_distance.to_f
      end

      def call
        return [] if @candidates.empty?

        placed = [ @candidates.first ]
        @candidates.drop(1).each do |candidate|
          break if placed.length >= MAX_MARKERS
          next unless candidate.distance - placed.last.distance >= @total * MIN_SPACING
          next unless changed?(placed.last.row, candidate.row)

          placed << candidate
        end
        placed.length == 1 ? [ halfway ] : placed
      end

      private

      def changed?(previous, current)
        Conditions.token(previous.weather_code) != Conditions.token(current.weather_code) ||
          (current.temperature - previous.temperature).abs >= TEMPERATURE_STEP ||
          sector_changed?(previous, current)
      end

      def sector_changed?(previous, current)
        return false if [ previous.wind_speed, current.wind_speed ].max < CALM_WIND

        sector(previous.wind_direction) != sector(current.wind_direction)
      end

      def sector(degrees) = ((degrees.to_f % 360) / 45.0).round % 8

      def halfway
        middle = @total / 2.0
        nearest = @candidates.min_by { |candidate| (candidate.distance - middle).abs }
        Marker.new(distance: middle, row: nearest.row)
      end
    end
  end
end
