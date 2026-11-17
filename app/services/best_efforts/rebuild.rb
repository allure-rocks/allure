# frozen_string_literal: true

module BestEfforts
  # Rebuilds every standard-distance best effort for one workout from its
  # stored track points. Deterministic and idempotent: tracks are immutable, so
  # a re-run replaces the same rows.
  #
  # The pure `compute` step can run before the caller's transaction, while
  # `persist` stays inside it (import, reanalysis, or backfill): a workout's
  # efforts are committed with the workout, and its `after_commit` records
  # recompute still reads current efforts. See PLAN_BEST_EFFORTS.md.
  class Rebuild
    class << self
      # Pure Ruby over the analyzer's in-memory segment metrics or the stored
      # track segments. Never touches the database. An effort the workout's
      # anomalies contest is left out: its time was never run
      # (PLAN_M1.md §8.10).
      def compute(sport:, segments:, workout_started_at:, context: "backfill", anomalies: nil)
        measure(:compute, context) do
          distances = Allure::Gpx::BestEfforts.distances_for(sport.slug)
          next [] if distances.empty? || segments.empty?

          Allure::Gpx::BestEfforts.find(segments:, distances:, workout_started_at:).reject do |effort|
            Allure::Gpx::Anomalies.contested_effort?(anomalies, start_distance: effort.start_offset_meters,
                                                                end_distance: effort.end_offset_meters)
          end
        end
      end

      # Times one phase on the Prometheus histogram without ever letting a
      # metrics failure change the domain result.
      def measure(phase, context)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        yield
      ensure
        observe(phase, context, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      end

      private

      def observe(phase, context, seconds)
        Metrics::Schema.define!
        Yabeda.allure.best_efforts_rebuild_duration_seconds.measure(
          { phase: phase.to_s, context: context.to_s }, seconds
        )
      rescue StandardError => error
        Rails.error.report(error, handled: true, context: { component: name, phase: phase.to_s })
      end
    end

    def initialize(workout:, context: "backfill")
      @workout = workout
      @context = context.to_s
    end

    # A credit row is rebuilt from its source's points and anomalies, with the
    # participant as athlete; a detached one has no points left and keeps its
    # frozen efforts (docs/dev/SHARED-ACTIVITIES.md).
    def call
      track = @workout.track_workout
      return [] unless track

      efforts = self.class.compute(
        sport: @workout.sport,
        segments: track.track_segments.reload,
        workout_started_at: track.started_at,
        context: @context,
        anomalies: track.data_anomalies
      )
      persist(efforts)
      efforts
    end

    # Persists precomputed efforts. Must run inside the caller's transaction.
    def persist(efforts)
      self.class.measure(:persist, @context) do
        BestEffort.transaction do
          @workout.best_efforts.delete_all
          efforts.each do |effort|
            @workout.best_efforts.create!(
              user: @workout.user,
              sport: @workout.sport,
              distance_key: effort.distance_key,
              distance_meters: effort.distance_meters,
              duration_seconds: effort.duration_seconds,
              started_at: effort.started_at,
              start_offset_meters: effort.start_offset_meters,
              end_offset_meters: effort.end_offset_meters
            )
          end
        end
      end
    end
  end
end
