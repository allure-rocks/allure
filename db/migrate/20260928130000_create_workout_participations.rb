# frozen_string_literal: true

# PLAN_TOGETHER.md lot 1: one row per shared activity between a source workout
# and another account. A participation is a `credit` (the source workout counts
# for the participant) or a `link` (the participant's own recording names the
# source workout). Confirmation is mutual: `owner_confirmed_at` and
# `participant_confirmed_at` are both required for the row to count, and a
# refusal is terminal for that account on that workout.
class CreateWorkoutParticipations < ActiveRecord::Migration[8.1]
  def change
    create_table :workout_participations do |t|
      t.references :workout, null: false, foreign_key: { on_delete: :cascade }
      t.references :participant_actor, null: false, foreign_key: { to_table: :actors, on_delete: :restrict }
      t.references :participant_workout, index: false, foreign_key: { to_table: :workouts, on_delete: :cascade }
      t.string :kind, null: false, default: "credit"
      t.string :origin, null: false, default: "invitation"
      t.datetime :owner_confirmed_at
      t.datetime :participant_confirmed_at
      t.datetime :declined_at
      t.datetime :withdrawn_at
      t.integer :detector_version
      t.text :wire_activity_uri
      t.timestamps
    end

    add_check_constraint :workout_participations,
                         "kind IN ('credit', 'link')",
                         name: "workout_participations_kind"
    add_check_constraint :workout_participations,
                         "origin IN ('invitation', 'detection')",
                         name: "workout_participations_origin"
    add_check_constraint :workout_participations,
                         "(kind = 'link') = (participant_workout_id IS NOT NULL)",
                         name: "workout_participations_link_workout"
    add_check_constraint :workout_participations,
                         "origin <> 'detection' OR kind = 'link'",
                         name: "workout_participations_detection_is_link"

    # One pace per pair on a workout while the row is live. A declined row is
    # still live, which is what makes a refusal terminal and closes the
    # re-invite vector; only a withdrawal frees the pair.
    add_index :workout_participations, [ :workout_id, :participant_actor_id ],
              unique: true,
              where: "withdrawn_at IS NULL",
              name: "index_workout_participations_live_pair"
    # One recording links to one source workout.
    add_index :workout_participations, :participant_workout_id,
              unique: true,
              where: "withdrawn_at IS NULL AND participant_workout_id IS NOT NULL",
              name: "index_workout_participations_live_recording"
  end
end
