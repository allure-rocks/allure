# frozen_string_literal: true

module Records
  # Recomputes the personal records for one (user, sport) scope: the seven
  # workout-column records, the biggest detected climb (`MC`), and the
  # standard-distance effort records. Winners are index-backed single-row
  # reads; a re-run is a no-op. NULL never wins (a type with no candidate keeps
  # no row); a genuine zero is a valid winner. Ties break on the earlier start,
  # then the earlier row, so the outcome is deterministic.
  class RecomputeService
    TYPES = {
      "AP" => { column: :average_pace, direction: :min },
      "AS" => { column: :average_speed, direction: :max },
      "BP" => { column: :best_pace, direction: :min },
      "FD" => { column: :distance, direction: :max },
      "HA" => { column: :ascent, direction: :max },
      "LD" => { column: :moving_time, direction: :max },
      "MS" => { column: :max_speed, direction: :max }
    }.freeze
    MAX_CLIMB = "MC"

    def initialize(user:, sport:)
      @user = user
      @sport = sport
    end

    def call
      return unless @user && @sport

      # Two match jobs of the same account finishing together recompute the
      # same scope; serializing them here keeps the second from racing the
      # first on the unique (user, sport, type) rows.
      Record.transaction do
        Record.connection.execute(
          Record.sanitize_sql_array([ "SELECT pg_advisory_xact_lock(hashtext(?))", "records:#{@user.id}:#{@sport.id}" ])
        )
        TYPES.each do |type, config|
          recompute_type(type, config)
        end
        recompute_max_climb
        recompute_effort_records
      end
    end

    private

    def recompute_type(type, config)
      winner = find_winner(config)
      if winner
        upsert_record(type, winner, value: winner.public_send(config[:column]))
      else
        Record.where(user: @user, sport: @sport, record_type: type).delete_all
      end
    end

    # A workout whose figure an anomaly contests never holds that record
    # (docs/dev/WORKOUT.md): the second best takes its place. A manual entry
    # holds none: a typed figure counts in the totals, never as a record
    # (docs/dev/MANUAL-ENTRY.md).
    def find_winner(config)
      column = config[:column]
      direction = config[:direction] == :min ? :asc : :desc
      @user.workouts
        .where.not(origin: "manual")
        .where(sport: @sport)
        .where.not(column => nil)
        .where.not("? = ANY(contested_metrics)", column.to_s)
        .order(column => direction, started_at: :asc, id: :asc)
        .first
    end

    def upsert_record(type, workout, value:)
      record = Record.find_or_initialize_by(user: @user, sport: @sport, record_type: type)
      record.assign_attributes(workout:, workout_started_at: workout.started_at, value:)
      holder_changed = record.new_record? || record.workout_id_changed?
      record.save!
      Webhooks::Events.record_achieved(record) if holder_changed
    end

    # The winner is the workout holding the largest detected climb. Detected
    # laps are rebuilt asynchronously, so `Segments::MatchWorkoutJob` and
    # `Laps::BackfillJob` recompute records once the climbs are fresh. A credit
    # row competes with the single number it carries, `credited_max_climb`
    # (docs/dev/SHARED-ACTIVITIES.md); ties go to the earlier workout.
    def recompute_max_climb
      if @sport.records_elevation
        candidates = [ recorded_max_climb, credited_max_climb ].compact
        winner = candidates.min_by { |workout, value| [ -value, workout.started_at, workout.id ] }
        if winner
          upsert_record(MAX_CLIMB, winner.first, value: winner.last)
          return
        end
      end
      Record.where(user: @user, sport: @sport, record_type: MAX_CLIMB).delete_all
    end

    def recorded_max_climb
      climb = DetectedLap
        .joins(:workout)
        .where(source: "climb", workouts: { user_id: @user.id, sport_id: @sport.id })
        .where.not(ascent: nil)
        .order(ascent: :desc, started_at: :asc, id: :asc)
        .includes(:workout)
        .first
      [ climb.workout, climb.ascent ] if climb
    end

    def credited_max_climb
      credit = @user.workouts.credit_rows_only
        .where(sport: @sport)
        .where.not(credited_max_climb: nil)
        .order(credited_max_climb: :desc, started_at: :asc, id: :asc)
        .first
      [ credit, credit.credited_max_climb ] if credit
    end

    def recompute_effort_records
      Allure::Gpx::BestEfforts.distances_for(@sport.slug).each do |distance_key, _meters|
        recompute_effort_record(distance_key)
      end
    end

    def recompute_effort_record(distance_key)
      winner = @user.best_efforts
        .where(sport: @sport, distance_key:)
        .order(duration_seconds: :asc, started_at: :asc, id: :asc)
        .includes(:workout)
        .first
      if winner
        record = EffortRecord.find_or_initialize_by(user: @user, sport: @sport, distance_key:)
        record.assign_attributes(
          workout: winner.workout,
          workout_started_at: winner.workout.started_at,
          distance_meters: winner.distance_meters,
          duration_seconds: winner.duration_seconds
        )
        holder_changed = record.new_record? || record.workout_id_changed?
        record.save!
        Webhooks::Events.record_achieved(record) if holder_changed
      else
        EffortRecord.where(user: @user, sport: @sport, distance_key:).delete_all
      end
    end
  end
end
