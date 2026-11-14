# frozen_string_literal: true

module Segments
  # The counters and personal-best flags a segment derives from its current
  # efforts (PLAN_SEGMENTS.md, PLAN_TOGETHER.md §6.4). Run after any change to
  # the effort set — a match, a released or dropped loop effort, a deleted
  # workout — so the stored figures never outlive the efforts they count.
  # Deterministic: a re-run is a no-op.
  class Refresh
    def self.call(segment) = new(segment).call

    def initialize(segment)
      @segment = segment
    end

    # The counters count recorded efforts only: a credited effort repeats a
    # traversal its source already counts, by an athlete who did not record
    # it (PLAN_TOGETHER.md §6.4). Personal bests cover credited efforts too.
    #
    # The segment row is locked first, so two refreshes of one segment never
    # interleave their writes over its efforts. `FOR NO KEY UPDATE` leaves the
    # `FOR KEY SHARE` a match takes while writing its own efforts compatible:
    # the refresh waits on that match's commit, never the other way round. A
    # segment deleted in the meantime is skipped. The record itself is not
    # reloaded, so a caller's assigned attributes survive.
    def call
      Segment.transaction do
        if Segment.where(id: @segment.id).lock("FOR NO KEY UPDATE").pick(:id)
          recorded = @segment.segment_efforts.joins(:workout).merge(Workout.recordings)
          @segment.update_columns(
            efforts_count: recorded.count,
            athletes_count: recorded.distinct.count("segment_efforts.user_id")
          )
          recompute_personal_bests
        end
      end
    end

    private

    # The fastest effort per (segment, user, sport) carries the badge; ties go
    # to the earlier start, then the earlier row. Every athlete on the segment
    # is recomputed, not only its creator: a shared course is matched against
    # other accounts' workouts too. A multi-sport segment keeps one personal
    # best per sport. One deterministic statement.
    def recompute_personal_bests
      winners = SegmentEffort.where(segment_id: @segment.id)
        .select("DISTINCT ON (user_id, sport_id) id")
        .order(:user_id, :sport_id, :elapsed_time, :started_at, :id)
      @segment.segment_efforts.update_all([ "personal_best = id IN (#{winners.to_sql})" ])
    end
  end
end
