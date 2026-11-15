# frozen_string_literal: true

module Comments
  # Active comment counts for one page of targets (PLAN_COMMENTS.md §5.5): one
  # grouped query per target class, so a feed page never counts per card. A
  # workout counts only the threads the viewer may read (docs/dev/PUBLISHING.md).
  class Counts
    def initialize(targets:, viewer: nil)
      @targets = Array(targets).compact
      @viewer = viewer
    end

    def call
      counts = @targets.index_with { 0 }
      count_notes(counts)
      count_workouts(counts)
      counts
    end

    private

    def count_notes(counts)
      records = @targets.grep(RemoteNote).index_by(&:id)
      return if records.empty?

      Comment.active.where(remote_note_id: records.keys).group(:remote_note_id).count.each do |id, count|
        counts[records.fetch(id)] = count
      end
    end

    def count_workouts(counts)
      records = @targets.grep(Workout).index_by(&:id)
      return if records.empty?

      readable = Workouts::ReadableAudiences.new(user: @viewer, workouts: records.values).call
      Comment.active.where(workout_id: records.keys).group(:workout_id, :audience).count.each do |(id, audience), count|
        counts[records.fetch(id)] += count if readable.fetch(id, []).include?(audience)
      end
    end
  end
end
