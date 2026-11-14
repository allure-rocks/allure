# frozen_string_literal: true

module Allure
  module Elevation
    # The terrain profile of a course (PLAN_ELEVATION.md §10): sampling along
    # its stored line and the figures the terrain answers give. A course is
    # short, so it is sampled finer than a workout, never coarser than the
    # configured interval unless the provider budget requires it.
    module CourseTerrain
      Point = Data.define(:latitude, :longitude)
      Line = Data.define(:points)
      ProfilePoint = Data.define(:distance, :elevation)
      Result = Data.define(:ascent, :descent, :min_elevation, :max_elevation, :average_grade, :profile)

      MIN_INTERVAL_METRES = 20.0
      TARGET_SAMPLES = 100

      module_function

      # `coordinates` are `[longitude, latitude]` pairs in course order.
      def samples(coordinates, interval_metres:, max_requests:)
        points = coordinates.map { |longitude, latitude| Point.new(latitude:, longitude:) }
        length = TrackGeometry.cumulative_distances([ Line.new(points:) ]).first&.last.to_f
        interval = (length / TARGET_SAMPLES).clamp(MIN_INTERVAL_METRES, [ interval_metres.to_f, MIN_INTERVAL_METRES ].max)

        result = sample(points, interval)
        while Sampler.chunks(result).length > max_requests
          interval *= 1.5
          result = sample(points, interval)
        end
        result
      end

      # One location every `interval` metres along the line, interpolated
      # between its vertices (a stored course may keep long straight edges),
      # plus the final vertex.
      def sample(points, interval)
        return [] if points.empty?

        result = [ Sampler::Sample.new(distance: 0.0, latitude: points.first.latitude, longitude: points.first.longitude) ]
        travelled = 0.0
        target = interval

        points.each_cons(2) do |from, to|
          length = Allure::Gpx::Geo.horizontal_distance(from.latitude, from.longitude, to.latitude, to.longitude)
          while length.positive? && target < travelled + length
            ratio = (target - travelled) / length
            result << Sampler::Sample.new(
              distance: target,
              latitude: from.latitude + ((to.latitude - from.latitude) * ratio),
              longitude: from.longitude + ((to.longitude - from.longitude) * ratio)
            )
            target += interval
          end
          travelled += length
        end

        if travelled > result.last.distance
          result << Sampler::Sample.new(distance: travelled, latitude: points.last.latitude, longitude: points.last.longitude)
        end
        result
      end

      # Nil unless the terrain answered every sample: a partial profile would
      # undercount the course. Sample distances are rescaled to the course's
      # stored distance, so the profile reads on the same axis as before.
      def metrics(samples, elevations, distance:)
        return if samples.length < 2 || elevations.length != samples.length
        return unless elevations.all? { |elevation| Gpx::Elevation.valid?(elevation) }

        length = samples.last.distance.to_f
        return unless length.positive?

        scale = distance.to_f.positive? ? distance.to_f / length : 1.0
        distances = samples.map { |sample| sample.distance * scale }
        filtered = Gpx::Elevation.filter(elevations, distances:, noise_class: :dem)
        ascent, descent = Gpx::Elevation.ascent_and_descent(filtered, threshold: Gpx::Elevation::DEM_THRESHOLD_METRES)
        course_distance = distances.last

        Result.new(
          ascent:,
          descent:,
          min_elevation: Gpx::Elevation.minimum(filtered),
          max_elevation: Gpx::Elevation.maximum(filtered),
          average_grade: Allure::Segments::Grade.from_elevations(filtered, distance: course_distance),
          profile: Allure::Segments::ElevationProfile.dump(
            distances.zip(filtered).map { |point_distance, elevation| ProfilePoint.new(distance: point_distance, elevation:) }
          )
        )
      end
    end
  end
end
