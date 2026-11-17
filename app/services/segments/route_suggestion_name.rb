# frozen_string_literal: true

module Segments
  # The name proposed when a recurring route is saved from its suggestion
  # (docs/dev/SEGMENTS.md): the departure and arrival places when the
  # toponymy named them, the workout title otherwise. The owner edits it in
  # the ordinary route form.
  class RouteSuggestionName
    MAX_LENGTH = 120

    def self.call(suggestion) = new(suggestion).call

    def initialize(suggestion)
      @suggestion = suggestion
    end

    def call
      workout = @suggestion.effective_reference_workout
      return if workout.nil?

      places = place_names(workout)
      name = if places.length >= 2
        "#{places.first} → #{places.last}"
      elsif places.length == 1
        places.first
      else
        workout.title.presence
      end
      name&.truncate(MAX_LENGTH)
    end

    private

    def place_names(workout)
      Array(workout.places).filter_map do |entry|
        next entry.strip.presence if entry.is_a?(String)

        place = entry.respond_to?(:to_h) ? entry.to_h : {}
        (place["name"] || place[:name]).to_s.strip.presence
      end
    end
  end
end
