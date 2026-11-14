# frozen_string_literal: true

# Two defects left stored `listed` snapshots stale: a duplicated `after_commit`
# declaration silently killed the publication-creation trigger, and the
# per-segment participation rule changed what "listed" means. One refresh job
# per segment catches every snapshot up; the default worker processes the
# queue after the deploy.
class RefreshSegmentListingsAfterParticipation < ActiveRecord::Migration[8.1]
  def up
    Segment.find_each(batch_size: 500) do |segment|
      Segments::RefreshListingJob.perform_later("segment", segment)
    end
  end

  def down
    # Nothing to revert: the jobs only recompute a derived snapshot.
  end
end
