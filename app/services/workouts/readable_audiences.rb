# frozen_string_literal: true

module Workouts
  # The publication audiences a reader may read on local workouts
  # (docs/dev/PUBLISHING.md): the audience of every active publication that
  # serves them — a follower the followers and the public ones, anyone else
  # the public one. The owner reads them all, even after the publications went
  # away. Each audience keeps its own comment thread, and a reactor is named
  # only to the readers of their reaction's audience (docs/dev/REACTIONS.md).
  # One query for a page of workouts, through the same rules as the profile
  # listing (WorkoutPublication.visible_to).
  class ReadableAudiences
    def initialize(user:, workouts:)
      @user = user
      @workouts = Array(workouts)
    end

    # { workout_id => [audience, ...] }
    def call
      result = @workouts.to_h { |workout| [ workout.id, [] ] }
      return result unless @user

      others = @workouts.reject do |workout|
        next false unless workout.user_id == @user.id

        result[workout.id] = Comment::AUDIENCES.dup
        true
      end
      return result if others.empty?

      WorkoutPublication.visible_to(@user).where(workout_id: others.map(&:id))
        .distinct.pluck(:workout_id, :audience)
        .each { |workout_id, audience| result[workout_id] << audience }
      result
    end

    def self.for(user:, workout:) = new(user:, workouts: [ workout ]).call.fetch(workout.id)
  end
end
