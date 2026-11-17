# frozen_string_literal: true

module Workouts
  # Changes a workout's sport and rebuilds every value that sport derives.
  # Stored metrics were computed with the old sport's thresholds
  # (`stopped_speed_threshold`, `records_elevation`, `grade_adjusted_pace?`),
  # so the original file is required and the analysis is forced to re-run; an
  # analysis failure rolls the whole change back. Segment matching and detected
  # laps follow asynchronously, and the model's `after_commit` recomputes the
  # records of both the old and the new sport once the best efforts are fresh.
  #
  # A change is recorded on the import entry as its provenance: a manual change
  # marks the entry `manual` so the re-detection backfill leaves it alone, and
  # the backfill reports its own changes as `detected` (docs/dev/VIRTUAL-PLATFORMS.md).
  # Crossing the virtual boundary also settles the toponymy: a virtual sport
  # discards it and is named from the platform's venue catalog, and a return to
  # a real sport re-enqueues geocoding.
  class SportChange
    class MissingOriginalFile < StandardError; end
    class ReanalysisFailed < StandardError; end

    DEFAULT_PROVENANCE = "manual"

    # `track:` injects an already-parsed original so the rebuild sweep does not
    # parse the same file twice (once for the facts, once for the forced
    # re-analysis this service runs).
    def initialize(workout:, sport:, provenance: DEFAULT_PROVENANCE, track: nil)
      @workout = workout
      @sport = sport
      @provenance = provenance
      @track = track
    end

    def call!
      return @workout if @workout.sport_id == @sport.id
      return change_manual_entry if @workout.manual?
      raise MissingOriginalFile, "workout has no original file" unless @workout.original_file.attached?

      previous_sport = @workout.sport
      begin
        Workout.transaction do
          @workout.update!(sport: @sport)
          Reanalyzer.new(workout: @workout, force: true, track: @track).call!
        end
      rescue Reanalyzer::MissingOriginalFileError => error
        raise MissingOriginalFile, error.message
      rescue StandardError => error
        raise ReanalysisFailed, error.message
      end

      # The forced re-analysis saves the workout again, which clears the tracked
      # sport change; recompute both scopes explicitly instead of relying on the
      # model callback alone.
      recompute_records(previous_sport)
      enqueue_segment_matching
      settle_toponymy(previous_sport)
      settle_weather
      mark_provenance
      @workout
    end

    private

    # A manual entry has no file and nothing derived from one: its figures
    # stay as typed, and the model's callback recomputes both record scopes
    # (docs/dev/MANUAL-ENTRY.md). A figure the new sport does not measure (an
    # ascent, a power) is refused rather than silently dropped.
    def change_manual_entry
      return @workout if @workout.update(sport: @sport)

      message = @workout.errors.full_messages.to_sentence
      @workout.restore_attributes(%i[sport_id])
      raise ReanalysisFailed, message
    end

    def recompute_records(previous_sport)
      [ previous_sport, @sport ].compact.uniq.each do |sport|
        Records::RecomputeService.new(user: @workout.user, sport:).call
      end
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: @workout.id })
    end

    def enqueue_segment_matching
      Segments::MatchWorkoutJob.perform_later(@workout)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: @workout.id })
    end

    def settle_toponymy(previous_sport)
      if @sport.virtual?
        @workout.toponymy&.destroy!
        VirtualVenueNamer.new(workout: @workout).call
      elsif previous_sport&.virtual?
        VirtualVenueNamer.new(workout: @workout).clear
        ToponymyRefresh.new(workout: @workout).call
      end
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: @workout.id })
    end

    # A virtual sport discards the weather; any other sport re-derives it
    # (its stopped speed shapes the wind analysis), offline when the plan
    # did not change (docs/dev/WEATHER.md).
    def settle_weather
      WeatherRefresh.new(workout: @workout).call
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: @workout.id })
    end

    # A single-file import has no ledger row; there is nothing to update then.
    def mark_provenance
      entry = WorkoutImportEntry.find_by(workout_id: @workout.id)
      return unless entry
      return if entry.sport_source == @provenance

      entry.update!(sport_source: @provenance)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: @workout.id })
    end
  end
end
