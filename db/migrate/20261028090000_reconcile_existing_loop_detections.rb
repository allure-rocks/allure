# frozen_string_literal: true

# Reconcile legacy duplicate loops and recover missed single traversals even
# on recordings already stamped by generation 3. Keep loop identities until
# matching has reassigned their efforts; only the matcher removes orphans.
class ReconcileExistingLoopDetections < ActiveRecord::Migration[8.1]
  # Solid Queue lives in another database. Commit the invalidation before its
  # worker can see the sweep; a failed enqueue leaves the migration unapplied
  # and retrying it is safe. Fresh installs have no recordings to enqueue.
  disable_ddl_transaction!

  def up
    execute <<~SQL
      UPDATE workouts
      SET loop_reuse_version = 0
      WHERE origin = 'import' AND start_point IS NOT NULL
        AND loop_reuse_version BETWEEN 1 AND 3
    SQL

    return unless select_value(<<~SQL)
      SELECT 1 FROM workouts
      WHERE origin = 'import' AND start_point IS NOT NULL
        AND loop_reuse_version = 0
      LIMIT 1
    SQL

    job = Segments::BackfillLoopReuseJob.set(priority: BacklogPriority::PRIORITY).perform_later
    unless job && job.successfully_enqueued?
      raise ActiveRecord::MigrationError, "Could not enqueue the loop reconciliation sweep; retry the migration."
    end
  end

  def down
    # Derived-data reconciliation has no inverse. Do not restore duplicates or
    # remove newly recognized efforts; already queued jobs remain safe to run.
  end
end
