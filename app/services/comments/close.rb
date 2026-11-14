# frozen_string_literal: true

module Comments
  # The owner's live switch on a workout's thread (PLAN_COMMENTS.md §5.4).
  # Closing keeps every existing comment and federates nothing; reopening
  # clears the instant. A publication whose profile closed comments stays
  # closed whatever this switch says.
  class Close
    class NotAllowed < StandardError; end

    def initialize(user:, workout:, closed:, now: Time.current)
      @user = user
      @workout = workout
      @closed = closed == true
      @now = now
    end

    def call!
      raise NotAllowed, "only the owner closes a thread" unless @user && @workout.user_id == @user.id

      # A live flag on the thread, not an edit of the workout: no validation or
      # derived-data callback has anything to say about it.
      if @closed
        @workout.update_column(:comments_closed_at, @now) if @workout.comments_closed_at.nil?
      elsif @workout.comments_closed_at
        @workout.update_column(:comments_closed_at, nil)
      end
      @workout
    end
  end
end
