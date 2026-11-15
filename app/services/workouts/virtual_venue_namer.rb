# frozen_string_literal: true

module Workouts
  # Names a virtual workout's place from the platform's venue catalog
  # (docs/dev/VIRTUAL-PLATFORMS.md): the world is recognised from the start point, and the
  # name is written to both the displayed list (`workouts.places`) and the
  # indexable `workout_place_names` rows the place filter searches. Nothing is
  # geocoded, and a workout whose world is unknown keeps an empty list rather
  # than a fabricated one. A non-virtual sport is left untouched.
  class VirtualVenueNamer
    PLACE_KIND = "virtual_venue"

    def initialize(workout:)
      @workout = workout
    end

    def call
      return [] unless @workout.sport.virtual?

      places = display_places
      apply(places)
      places
    end

    # Used when a workout leaves the virtual world for a real sport: the venue
    # name must not linger while geocoding is queued again (SportChange).
    def clear
      apply([])
      []
    end

    private

    def display_places
      venue = locate_venue
      return [] unless venue

      [ { "name" => venue.name, "kind" => PLACE_KIND } ]
    end

    def locate_venue
      platform = Allure::Virtual::Platforms.for_creator(@workout.source)
      return nil unless platform

      point = @workout.start_point
      return nil if point.nil?

      platform.venue_at(longitude: point.x, latitude: point.y)
    end

    def apply(places)
      @workout.update_columns(places:) if @workout.places != places
      sync_place_names(places)
    end

    # The same contract as Workouts::PlaceNamer: one row per recorded place,
    # positional, cleared before rewriting so a renamed world never leaves a
    # stale suggestion behind.
    def sync_place_names(places)
      rows = places.each_with_index.map do |place, index|
        { name: place.fetch("name"), kind: place.fetch("kind"), position: index }
      end
      existing = @workout.place_names.order(:position).pluck(:name, :kind)
      return if existing == rows.map { |row| [ row.fetch(:name), row.fetch(:kind) ] }

      now = Time.current
      WorkoutPlaceName.transaction do
        @workout.place_names.delete_all
        next if rows.empty?

        WorkoutPlaceName.insert_all(
          rows.map do |row|
            row.merge(workout_id: @workout.id, user_id: @workout.user_id, created_at: now, updated_at: now)
          end
        )
      end
      @workout.association(:place_names).reset
    end
  end
end
