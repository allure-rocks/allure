# frozen_string_literal: true

module Segments
  # Atomic deletion boundary: withdrawal persistence and segment destruction
  # commit together; Delete expansion is enqueued only after commit. Mirrors
  # Workouts::WorkoutDeletion (PLAN_SEGMENTS_FEDERATION.md §9.4).
  class SegmentDeletion
    Result = Data.define(:segment_id, :publication, :delete_event)

    def initialize(user:, segment:)
      @user = user
      @segment = segment
    end

    def call!
      raise ActiveRecord::RecordNotFound unless @segment.user_id == @user.id

      @segment.association(:active_publication).reset
      unless @segment.active_publication
        segment_id = @segment.id
        Segment.transaction { destroy_locked! }
        return Result.new(segment_id:, publication: nil, delete_event: nil)
      end

      withdrawal = PublicationWithdrawal.new(user: @user, segment: @segment)
      result = nil
      segment_id = @segment.id

      Segment.transaction do
        result = withdrawal.persist!
        destroy_locked!
      end

      PublicationWithdrawal.enqueue_expansion(result.delete_event)
      Result.new(segment_id:, publication: result.publication, delete_event: result.delete_event)
    end

    private

    # The segment row is locked before its efforts are destroyed: a match
    # writing efforts on it holds `FOR KEY SHARE` on the same row first
    # (`Segments::MatchWorkoutJob#persist_matches`), so one waits for the
    # other's commit instead of each holding efforts the other needs.
    def destroy_locked!
      @segment.lock!
      @segment.destroy!
    end
  end
end
