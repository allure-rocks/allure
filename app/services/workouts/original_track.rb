# frozen_string_literal: true

module Workouts
  # Opens and parses a workout's immutable original file with the parser that
  # matches its stored import format. Reanalysis and terrain-elevation sampling
  # both read the same source so their geometry never diverges.
  #
  # A workout imported with a time shift (PLAN_DEMO.md §4) re-applies it here,
  # so every re-analysis derives the same dates the import did instead of
  # falling back to the original file's own recording day.
  class OriginalTrack
    class MissingOriginalFileError < StandardError; end

    def initialize(workout:)
      @workout = workout
    end

    def call
      raise MissingOriginalFileError, "workout has no original file" unless @workout.original_file.attached?

      format = Allure::ImportFormat::ALL.find { |candidate| candidate.key == @workout.import_format }
      raise ArgumentError, "unsupported workout import format: #{@workout.import_format}" unless format

      track = @workout.original_file.blob.open { |file| format.parser.parse(file) }
      shift = @workout.time_shift_seconds.to_i
      shift.zero? ? track : track.shifted(shift)
    end
  end
end
