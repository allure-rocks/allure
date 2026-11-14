# frozen_string_literal: true

module Workouts
  # Assembles the workout's places from what the toponymy already stores: the
  # departure, the curated route markers, and the arrival. Two consumers:
  #
  # - the displayed list (`workout_toponymies.places` and `workouts.places`),
  #   deduplicated by name and capped at PLACE_LIMIT;
  # - the indexable `workout_place_names` rows, one per recorded place in route
  #   order, which is what the owner's filter and autocomplete search.
  #
  # Pure and offline: it issues no geocoding request, reads no track geometry,
  # and clears previous output rather than leaving it stale.
  class PlaceNamer
    # Stored on workout_toponymies.places_algorithm_version so a later change
    # to the assembly is an operator backfill, never a re-geocoding.
    ALGORITHM_VERSION = 2
    PLACE_LIMIT = 3
    MAX_NAME_LENGTH = 120

    def initialize(workout:)
      @workout = workout
    end

    def call
      # A virtual workout's place comes from the platform's venue catalog
      # (Workouts::VirtualVenueNamer); this assembly must never overwrite it.
      return if @workout.sport.virtual?

      toponymy = @workout.toponymy
      return if toponymy.nil?
      return unless toponymy.ready? || toponymy.partial?

      markers = marker_entries(toponymy)
      places = display_places(toponymy, markers)
      recorded = recorded_places(toponymy, markers)

      sync_toponymy(toponymy, places)
      @workout.update_columns(places:) if @workout.places != places
      sync_place_names(recorded)
      places
    end

    private

    # The endpoints come first so the cap can never drop the arrival of a
    # point-to-point route; the arrival of a loop is the departure, collapsed
    # by the name deduplication.
    def display_places(toponymy, markers)
      entries = [
        place_entry(toponymy.start_place, 0.0),
        place_entry(toponymy.finish_place, @workout.distance.to_f),
        *markers
      ].compact

      entries
        .uniq { |entry| normalize(entry.fetch(:name)) }
        .first(PLACE_LIMIT)
        .sort_by { |entry| entry.fetch(:distance) }
        .map { |entry| { "name" => entry.fetch(:name), "kind" => entry.fetch(:kind) } }
    end

    # Every recorded place, deduplicated by name and kept in route order: the
    # departure, the markers by distance, the arrival.
    def recorded_places(toponymy, markers)
      entries = [
        place_entry(toponymy.start_place, 0.0),
        *markers.sort_by { |entry| entry.fetch(:distance) },
        place_entry(toponymy.finish_place, @workout.distance.to_f)
      ].compact

      entries.uniq { |entry| normalize(entry.fetch(:name)) }
    end

    def marker_entries(toponymy)
      Array(toponymy.markers).filter_map do |marker|
        value = marker.respond_to?(:to_h) ? marker.to_h : {}
        distance = value["distance"] || value[:distance]
        next unless distance.is_a?(Numeric) && distance.to_f.finite?

        entry = place_entry(value, distance.to_f)
        entry&.merge(rank: rank_of(value))
      end.sort_by { |entry| entry.fetch(:rank) }
    end

    def place_entry(place, distance)
      value = place.respond_to?(:to_h) ? place.to_h : {}
      name = (value["name"] || value[:name]).to_s.strip.truncate(MAX_NAME_LENGTH)
      return if name.empty?

      { name:, kind: (value["kind"] || value[:kind]).to_s, distance: }
    end

    def rank_of(value)
      rank = value["rank"] || value[:rank]
      return Float::INFINITY unless rank.is_a?(Numeric) && rank.positive?

      rank
    end

    def sync_toponymy(toponymy, places)
      return if toponymy.places == places && toponymy.places_algorithm_version == ALGORITHM_VERSION

      toponymy.update_columns(places:, places_algorithm_version: ALGORITHM_VERSION)
    end

    def sync_place_names(recorded)
      rows = recorded.each_with_index.map do |entry, index|
        { name: entry.fetch(:name), kind: entry.fetch(:kind), position: index }
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

    def normalize(name)
      I18n.transliterate(name.to_s).downcase.strip
    end
  end
end
