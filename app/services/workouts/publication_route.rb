# frozen_string_literal: true

module Workouts
  class PublicationRoute
    class Unavailable < StandardError; end

    def initialize(user:, workout:, profile:)
      @user = user
      @workout = workout
      @profile = profile
    end

    attr_reader :endpoint_coverage, :endpoint_visibility

    def call!
      coordinates = source_coordinates
      zones = @user.privacy_zones.active.map(&:to_value)
      settings = @profile.settings
      mask_start = settings["mask_start"]
      mask_finish = settings["mask_finish"]

      Allure::Federation::Privacy::EndpointMaskPolicy.new(
        segments: coordinates,
        zones:,
        mask_start:,
        mask_finish:
      ).call

      @endpoint_coverage = coverage_for(coordinates, zones)

      filtered = Allure::Federation::Privacy::ZoneFilter.new(
        segments: coordinates,
        zones:,
        preserve_start: mask_start != true,
        preserve_finish: mask_finish != true
      ).call
      raise Unavailable, "filtered route is not usable" unless filtered.usable?

      @endpoint_visibility = visibility_for(filtered, coordinates)
      filtered
    end

    private

    def coverage_for(coordinates, zones)
      filter = Allure::Federation::Privacy::ZoneFilter.new(segments: coordinates, zones:)
      {
        start: filter.covered?(coordinates.first.first),
        finish: filter.covered?(coordinates.last.last)
      }
    end

    # Whether each source endpoint survived filtering. A fully covered segment
    # keeps no exemption, so an unmasked endpoint can still be absent; only the
    # surviving ones are worth warning about.
    def visibility_for(filtered, coordinates)
      source_start = coordinates.first.first
      source_finish = coordinates.last.last
      {
        start: filtered.segments.any? { |segment| segment.first == source_start },
        finish: filtered.segments.any? { |segment| segment.last == source_finish }
      }
    end

    def source_coordinates
      @workout.track_segments.map do |segment|
        unless segment.points.is_a?(Array)
          raise Allure::Federation::Privacy::ZoneFilter::InvalidInput, "source route points are invalid"
        end

        segment.points.map do |point|
          longitude_key = Allure::Gpx::PointSerializer::KEY_LONGITUDE
          latitude_key = Allure::Gpx::PointSerializer::KEY_LATITUDE
          unless point.is_a?(Hash) && point.key?(longitude_key) && point.key?(latitude_key)
            raise Allure::Federation::Privacy::ZoneFilter::InvalidInput, "source route point is invalid"
          end

          [ Float(point.fetch(longitude_key)), Float(point.fetch(latitude_key)) ]
        rescue ArgumentError, TypeError
          raise Allure::Federation::Privacy::ZoneFilter::InvalidInput, "source route point is invalid"
        end
      end
    end
  end
end
