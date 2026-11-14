# frozen_string_literal: true

module Allure
  module Geometry
    module LoopDetector
      Candidate = Data.define(
        :start_index,
        :end_index,
        :travelled_distance_meters,
        :closure_distance_meters,
        :coordinates
      ) do
        def initialize(start_index:, end_index:, travelled_distance_meters:, closure_distance_meters:, coordinates:)
          super
        end
      end

      RETRACE_SAMPLE_COUNT = 64
      # Once a closure is rejected as retraced, the next one is only checked
      # after this much further travel, and the scan gives up after this many
      # rejections: a stop at the start, or a track circling it, would
      # otherwise run the Fréchet guard at every point.
      RETRACE_CHECK_SPACING = 5.0
      MAX_RETRACE_CHECKS = 200

      module_function

      def detect(coordinates, min_loop_distance: 400.0, closure_radius: 30.0)
        points = normalize_coordinates(coordinates)
        min_loop_distance = positive_float(min_loop_distance, "min_loop_distance")
        closure_radius = non_negative_float(closure_radius, "closure_radius")
        travelled = 0.0
        lengths = [ 0.0 ]
        rejected = 0
        last_rejected_at = nil

        points.each_cons(2).with_index do |(first, second), index|
          travelled += horizontal_distance(first, second)
          lengths << travelled
          end_index = index + 1
          next if travelled < min_loop_distance

          closure_distance = horizontal_distance(points.first, second)
          next if closure_distance > closure_radius
          next if last_rejected_at && travelled - last_rejected_at < RETRACE_CHECK_SPACING

          if retraced?(points, lengths, end_index, closure_radius)
            rejected += 1
            return nil if rejected >= MAX_RETRACE_CHECKS

            last_rejected_at = travelled
            next
          end

          return Candidate.new(
            start_index: 0,
            end_index: end_index,
            travelled_distance_meters: travelled,
            closure_distance_meters: closure_distance,
            coordinates: points[0..end_index].freeze
          )
        end

        nil
      end

      def normalize_coordinates(coordinates)
        points = Array(coordinates).map do |coordinate|
          values = Array(coordinate)
          raise ArgumentError, "invalid coordinate" unless values.length == 2

          longitude, latitude = values
          longitude = Float(longitude)
          latitude = Float(latitude)
          unless longitude.finite? && latitude.finite? && longitude.between?(-180, 180) && latitude.between?(-90, 90)
            raise ArgumentError, "invalid coordinate"
          end

          [ longitude, latitude ].freeze
        end
        raise ArgumentError, "polyline requires at least two coordinates" if points.length < 2

        points
      rescue TypeError, ArgumentError => error
        raise error if error.message.match?(/polyline|coordinate/)

        raise ArgumentError, "invalid coordinates", cause: error
      end

      def positive_float(value, name)
        value = Float(value)
        raise ArgumentError, "#{name} must be positive" unless value.finite? && value.positive?

        value
      rescue TypeError, ArgumentError => error
        raise error if error.message.include?(name)

        raise ArgumentError, "invalid #{name}", cause: error
      end

      def non_negative_float(value, name)
        value = Float(value)
        raise ArgumentError, "#{name} must be non-negative" unless value.finite? && value >= 0

        value
      rescue TypeError, ArgumentError => error
        raise error if error.message.include?(name)

        raise ArgumentError, "invalid #{name}", cause: error
      end

      def retraced?(points, lengths, end_index, closure_radius)
        sampled = prefix_samples(points, lengths, end_index)
        deviation = Allure::Geometry::Frechet.distance(sampled, sampled.reverse, band: nil)
        deviation <= closure_radius
      end

      # `Resampler.resample(points[0..end_index], count: RETRACE_SAMPLE_COUNT)`
      # read from the whole track's cumulative lengths: each sample is found
      # by binary search instead of re-measuring and copying the prefix.
      def prefix_samples(points, lengths, end_index)
        total = lengths[end_index]
        interval = total / (RETRACE_SAMPLE_COUNT - 1).to_f
        Array.new(RETRACE_SAMPLE_COUNT) do |sample_index|
          target = interval * sample_index
          if total.zero? || target <= 0
            points.first
          elsif target >= total
            points[end_index]
          else
            index = (1..end_index).bsearch { |candidate| lengths[candidate] >= target } || 1
            edge_length = lengths[index] - lengths[index - 1]
            if edge_length.zero?
              points[index]
            else
              fraction = (target - lengths[index - 1]) / edge_length
              Allure::Geometry::Resampler.interpolate(points[index - 1], points[index], fraction)
            end
          end
        end.freeze
      end

      def horizontal_distance(first, second)
        Allure::Gpx::Geo.horizontal_distance(first[1], first[0], second[1], second[0])
      end
    end
  end
end
