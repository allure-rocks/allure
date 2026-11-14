# frozen_string_literal: true

module Allure
  module Weather
    # Where and when to ask for the weather (PLAN_WEATHER.md §3): the
    # athlete's position at the start, at every whole UTC hour inside the
    # activity and at the finish, rounded to a 0.1° grid cell before anything
    # leaves the instance. Cells are deduplicated; each keeps the mean recorded
    # elevation of its samples, rounded to 10 m, so a re-analysis that barely
    # moves the profile asks nothing again.
    #
    # Input points answer `time`, `latitude`, `longitude` and `elevation`
    # (`Allure::Segments::Point` from the stored track). Positionless points
    # are ignored; an untimed or positionless track yields an empty plan.
    class Sampler
      GRID_DEGREES = 0.1
      ELEVATION_ROUNDING = 10
      HOUR = 3_600
      MAX_SAMPLES = 50

      Sample = Data.define(:time, :cell)

      Plan = Data.define(:cells, :samples) do
        def empty? = samples.empty?

        def start_date = Time.at(samples.first.time).utc.to_date

        def end_date = Time.at(samples.last.time).utc.to_date

        def to_json_samples
          samples.map { |sample| { "t" => sample.time, "cell" => sample.cell } }
        end

        def to_json_cells
          cells.map { |cell| { "lat" => cell.latitude, "lon" => cell.longitude, "ele" => cell.elevation } }
        end
      end

      def self.call(points) = new(points).call

      def self.round_coordinate(value) = ((value / GRID_DEGREES).round * GRID_DEGREES).round(1)

      def initialize(points)
        @points = Array(points).select { |point| !point.latitude.nil? && !point.longitude.nil? && point.time }
      end

      def call
        return Plan.new(cells: [], samples: []) if @points.length < 2

        first = @points.first.time.to_i
        last = @points.last.time.to_i
        return Plan.new(cells: [], samples: []) unless last > first

        build(sample_times(first, last))
      end

      private

      def sample_times(first, last)
        hours = []
        hour = (first / HOUR + 1) * HOUR
        while hour < last
          hours << hour
          hour += HOUR
        end
        hours = thin(hours, MAX_SAMPLES - 2)
        [ first, *hours, last ]
      end

      def thin(values, limit)
        return values if values.length <= limit

        step = values.length.to_f / limit
        Array.new(limit) { |index| values[(index * step).floor] }
      end

      def build(times)
        keys = {}
        elevations = Hash.new { |hash, key| hash[key] = [] }
        samples = times.map do |time|
          point = point_at(time)
          key = [ self.class.round_coordinate(point.latitude), self.class.round_coordinate(point.longitude) ]
          keys[key] ||= keys.length
          elevations[key] << point.elevation.to_f unless point.elevation.nil?
          Sample.new(time:, cell: keys[key])
        end

        cells = keys.keys.map do |latitude, longitude|
          values = elevations[[ latitude, longitude ]]
          elevation = values.empty? ? nil : ((values.sum / values.length) / ELEVATION_ROUNDING).round * ELEVATION_ROUNDING
          OpenMeteo::Location.new(latitude:, longitude:, elevation:)
        end
        Plan.new(cells:, samples:)
      end

      # The recorded point closest in time (points are time-ordered).
      def point_at(time)
        index = @points.bsearch_index { |point| point.time.to_i >= time } || (@points.length - 1)
        return @points[index] if index.zero?

        before = @points[index - 1]
        after = @points[index]
        (time - before.time.to_i) <= (after.time.to_i - time) ? before : after
      end
    end
  end
end
