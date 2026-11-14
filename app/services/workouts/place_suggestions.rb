# frozen_string_literal: true

module Workouts
  # The owner's recorded place names for the workout list's place
  # autocomplete, most used first (DESIGN.md §13). One aggregate over the
  # derived `workout_place_names` rows, scoped to the account: names only,
  # never a coordinate, never another account's place.
  class PlaceSuggestions
    DEFAULT_LIMIT = 10
    MAX_QUERY_LENGTH = 120

    def initialize(user:, query: nil, limit: DEFAULT_LIMIT)
      @user = user
      @query = query.to_s.strip.truncate(MAX_QUERY_LENGTH)
      @limit = limit
    end

    def call
      scope = WorkoutPlaceName.where(user: @user)
      if @query.present?
        scope = scope.where("name ILIKE ? ESCAPE '\\'", "%#{escape_like(@query)}%")
      end

      scope
        .group(:name)
        .order(Arel.sql("COUNT(*) DESC"), :name)
        .limit(@limit)
        .pluck(:name)
    end

    private

    def escape_like(value)
      value.gsub(/[%_\\]/) { |match| "\\#{match}" }
    end
  end
end
