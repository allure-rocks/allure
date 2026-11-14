# frozen_string_literal: true

# PLAN_TOGETHER.md §7, lot 4 slice 4c: a confirmed invitation from another
# instance gives the local account a credit row like a local credit, built
# from the received note's figures. The row names its participation (one
# credit row per participation); a credit row has one source, local or
# remote, and only a credit names one.
class AddRemoteParticipationToWorkouts < ActiveRecord::Migration[8.1]
  def up
    add_reference :workouts, :remote_participation, index: false,
                                                    foreign_key: { on_delete: :nullify }
    add_index :workouts, :remote_participation_id, unique: true, where: "remote_participation_id IS NOT NULL",
                                                   name: "index_workouts_on_remote_participation"
    add_check_constraint :workouts,
                         "remote_participation_id IS NULL OR " \
                         "(origin = 'credit' AND credited_from_workout_id IS NULL)",
                         name: "workouts_remote_credit_shape"
  end

  def down
    remove_check_constraint :workouts, name: "workouts_remote_credit_shape"
    remove_index :workouts, name: "index_workouts_on_remote_participation"
    remove_reference :workouts, :remote_participation, foreign_key: true
  end
end
