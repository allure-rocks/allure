# frozen_string_literal: true

module Participations
  # Copies the column contract of PLAN_TOGETHER.md §3.2 from an attached
  # credit row's source, and nothing else: the credited metric set, the title,
  # the matcher's noise class, the analysis version, the contested metrics
  # records must skip, and the credited biggest climb. A detached row is
  # frozen and left as it is. Saving through the model lets its records
  # hooks recompute the participant's records.
  class CreditSync
    SYNCED_COLUMNS = %w[
      sport_id started_at duration moving_time pause_time distance ascent descent
      average_speed average_pace max_speed best_pace title elevation_filter
      analysis_version contested_metrics
    ].freeze

    def self.attributes_from(source)
      source.attributes.slice(*SYNCED_COLUMNS).merge("credited_max_climb" => max_climb(source))
    end

    # One number from the owner's detected climbs, never the climb itself:
    # its name and shape stay the owner's (PLAN_TOGETHER.md §4.1, §6.3).
    def self.max_climb(source)
      return unless source.sport.records_elevation

      DetectedLap.where(workout_id: source.id, source: "climb").maximum(:ascent)
    end

    def initialize(credit_row)
      @credit_row = credit_row
    end

    def call
      source = @credit_row.credited_from
      return @credit_row unless @credit_row.credit? && source

      @credit_row.assign_attributes(self.class.attributes_from(source))
      @credit_row.save! if @credit_row.changed?
      derive
    end

    # The participant's derived rows follow the source's points
    # (PLAN_TOGETHER.md §6.3): best efforts now, then the records they and the
    # credited climb feed, then the segment matching on its own queue. Run
    # outside any open transaction, so the queued match reads committed rows.
    def derive
      return @credit_row unless @credit_row.credit? && @credit_row.credited_from

      BestEfforts::Rebuild.new(workout: @credit_row, context: "credit").call
      Records::RecomputeService.new(user: @credit_row.user, sport: @credit_row.sport).call
      Segments::MatchWorkoutJob.perform_later(@credit_row)
      @credit_row
    end
  end
end
