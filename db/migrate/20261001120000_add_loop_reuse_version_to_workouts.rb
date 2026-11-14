# frozen_string_literal: true

# PLAN_DERIVATIONS.md: the loop-reuse reconciliation marker. Zero means the
# workout's detected loop has not been reconciled under the current reuse
# predicate (Segments::LoopReuse::VERSION), so BackfillLoopReuseJob re-runs its
# matching; MatchWorkoutJob stamps the current version when it completes.
# Existing rows start at zero and are reconciled by the next sweep.
class AddLoopReuseVersionToWorkouts < ActiveRecord::Migration[8.1]
  def change
    add_column :workouts, :loop_reuse_version, :integer, default: 0, null: false
    add_check_constraint :workouts, "loop_reuse_version >= 0", name: "workouts_loop_reuse_version"
    add_index :workouts, [ :loop_reuse_version, :id ]
  end
end
