# frozen_string_literal: true

module BestEfforts
  # Bounded, resumable best-effort rebuild for every existing workout. The
  # stored track points are enough: no original file and no re-analysis are
  # needed. `sport_slug` narrows the sweep to one sport when a new distance
  # profile is added. Records are recomputed once per affected (user, sport) at
  # the end of each batch. See PLAN_BEST_EFFORTS.md.
  class BackfillJob < ApplicationJob
    BATCH_SIZE = 100

    queue_as :default

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5

    def perform(after_id: 0, sport_slug: nil)
      # An attached credit row is rebuilt from its source's points; a detached
      # one keeps its frozen efforts (PLAN_TOGETHER.md §6.3).
      scope = Workout.where("workouts.origin = 'import' OR workouts.credited_from_workout_id IS NOT NULL")
        .where("workouts.id > ?", after_id)
      if sport_slug.present?
        scope = scope.joins(:sport).where(sports: { slug: sport_slug })
      else
        scope = scope.includes(:sport)
      end
      workouts = scope.order("workouts.id").limit(BATCH_SIZE).to_a
      pairs = []
      workouts.each do |workout|
        next unless Allure::Gpx::BestEfforts.profile_for(workout.sport.slug)

        BestEfforts::Rebuild.new(workout:, context: "backfill").call
        pairs << [ workout.user_id, workout.sport_id ]
      end

      recompute_records(pairs)

      last_id = workouts.last&.id
      self.class.perform_later(after_id: last_id, sport_slug:) if workouts.length == BATCH_SIZE
    end

    private

    def recompute_records(pairs)
      pairs.uniq.each do |user_id, sport_id|
        user = User.find_by(id: user_id)
        sport = Sport.find_by(id: sport_id)
        Records::RecomputeService.new(user:, sport:).call if user && sport
      end
    end
  end
end
