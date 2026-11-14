# frozen_string_literal: true

module Workouts
  class WorkoutDeletion
    Result = Data.define(:workout_id, :publications, :delete_events)

    def initialize(user:, workout:)
      @user = user
      @workout = workout
    end

    # Atomic lifecycle boundary (PLAN_M4_5 Slice 4): withdrawal persistence and
    # source destruction commit together, for every audience's publication
    # (PLAN_AUDIENCES.md §4). A publication still inside its safety delay is
    # cancelled in the same transaction — no Delete activity exists for one,
    # because nothing was ever shared. Delete expansion is enqueued only after
    # commit; a destroy failure rolls back the withdrawal.
    def call!
      raise ActiveRecord::RecordNotFound unless @workout.user_id == @user.id

      @workout.reset_publications
      Webhooks::Events.workout_deleted(@user, @workout.to_param)
      active = @workout.active_publications.to_a
      scheduled = @workout.scheduled_publications.to_a
      workout_id = @workout.id

      if active.empty? && scheduled.empty?
        @workout.destroy!
        return Result.new(workout_id:, publications: [], delete_events: [])
      end

      results = []
      Workout.transaction do
        results = active.map do |publication|
          PublicationWithdrawal.new(user: @user, workout: @workout, publication:, reason: "workout_deleted").persist!
        end
        scheduled.each do |publication|
          ScheduledPublicationCancellation.new(user: @user, publication:).call!
        end
        @workout.destroy!
      end

      delete_events = results.filter_map(&:delete_event)
      delete_events.each { |event| PublicationWithdrawal.enqueue_expansion(event) }
      Result.new(workout_id:, publications: results.map(&:publication), delete_events:)
    end
  end
end
