# frozen_string_literal: true

module Segments
  # Batched board reads shared by the standings and the index: the ranking a
  # viewer reads per (segment, sport) — best effort per athlete, ordered like
  # the board — and the viewer's own best effort per (segment, sport), ranked
  # or not (PLAN_SEGMENTS.md §8.2). Two queries cover a whole page of courses.
  module Rankings
    module_function

    def by_segment_and_sport(segment_ids, viewer:)
      Segments::Listing.for_segments(segment_ids, viewer:)
        .includes(:user, :sport)
        .group_by { |effort| [ effort.segment_id, effort.sport_id ] }
        .transform_values do |efforts|
          efforts.group_by(&:user_id)
            .map { |_, athlete_efforts| athlete_efforts.min_by { |effort| [ effort.elapsed_time, effort.started_at, effort.id ] } }
            .sort_by { |effort| [ effort.elapsed_time, effort.started_at, effort.id ] }
        end
    end

    def viewer_best_by_segment(segment_ids, viewer)
      SegmentEffort
        .where(segment_id: segment_ids, user: viewer)
        .includes(:sport)
        .order(:elapsed_time, :started_at, :id)
        .group_by(&:segment_id)
        .transform_values do |efforts|
          efforts.group_by(&:sport_id).transform_values(&:first)
        end
    end
  end
end
