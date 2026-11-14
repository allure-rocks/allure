# frozen_string_literal: true

module Workouts
  class PublicationReadiness
    Result = Data.define(:ready, :warnings) do
      def ready? = ready
    end

    def initialize(user:, workout:, profile:)
      @user = user
      @workout = workout
      @profile = profile
    end

    def call
      return Result.new(ready: false, warnings: [ :followers_unavailable ]) unless @profile.publishable?
      # A positionless recording has no route to share (PLAN_NO_GPS.md §7).
      return Result.new(ready: false, warnings: [ :no_geometry ]) unless @workout.positioned?

      route = PublicationRoute.new(user: @user, workout: @workout, profile: @profile)
      filtered = route.call!
      warnings = []
      warnings << :no_interior_points unless filtered.interior_points_removed?
      warnings.concat(endpoint_visibility_warnings(route.endpoint_coverage, route.endpoint_visibility))
      Result.new(ready: true, warnings:)
    rescue Allure::Federation::Privacy::EndpointMaskPolicy::UnsatisfiedEndpoint => error
      Result.new(ready: false, warnings: [ "endpoint_mask_#{error.endpoint}".to_sym ])
    rescue Allure::Federation::Privacy::ZoneFilter::InvalidInput,
           Allure::Federation::Privacy::ZoneFilter::FilteringError,
           PublicationRoute::Unavailable
      Result.new(ready: false, warnings: [ :route_unavailable ])
    end

    private

    # An endpoint the profile leaves unmasked stays visible even inside an
    # active zone; the publisher must say so before sharing.
    def endpoint_visibility_warnings(coverage, visibility)
      settings = @profile.settings
      warnings = []
      if settings["mask_start"] != true && coverage&.dig(:start) && visibility&.dig(:start)
        warnings << :endpoint_visible_start
      end
      if settings["mask_finish"] != true && coverage&.dig(:finish) && visibility&.dig(:finish)
        warnings << :endpoint_visible_finish
      end
      warnings
    end
  end
end
