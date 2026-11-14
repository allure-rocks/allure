# frozen_string_literal: true

# Persists the workout-level place derived from the stored toponymy: the
# structured selection next to its inputs on `workout_toponymies`, and the
# compact denormalization the owner lists read on `workouts`. Adds the
# places-backfill maintenance action to the operator audit log.
class AddPlacesToWorkoutsAndToponymies < ActiveRecord::Migration[8.1]
  ACTIONS = %w[
    domain_blocked domain_unblocked actor_blocked actor_unblocked
    peer_policy_set peer_policy_removed media_retried
    job_retried job_discarded jobs_retried jobs_discarded
    queue_paused queue_resumed analysis_backfill_enqueued
    elevation_backfill_enqueued
    publication_withdrawn
    account_suspended account_reinstated
    invitation_created invitation_revoked
    places_backfill_enqueued
  ].freeze

  PREVIOUS_ACTIONS = (ACTIONS - %w[places_backfill_enqueued]).freeze

  def up
    add_column :workouts, :places, :jsonb, null: false, default: []
    add_check_constraint :workouts, "jsonb_typeof(places) = 'array'", name: "workouts_places_array"

    add_column :workout_toponymies, :places, :jsonb, null: false, default: []
    add_column :workout_toponymies, :places_algorithm_version, :integer, null: false, default: 0
    add_check_constraint :workout_toponymies,
                         "jsonb_typeof(places) = 'array'",
                         name: "workout_toponymies_places_array"
    add_check_constraint :workout_toponymies,
                         "places_algorithm_version >= 0",
                         name: "workout_toponymies_places_algorithm_version"

    replace_action_constraint(ACTIONS)
  end

  def down
    replace_action_constraint(PREVIOUS_ACTIONS)

    remove_check_constraint :workout_toponymies, name: "workout_toponymies_places_algorithm_version"
    remove_check_constraint :workout_toponymies, name: "workout_toponymies_places_array"
    remove_column :workout_toponymies, :places_algorithm_version
    remove_column :workout_toponymies, :places

    remove_check_constraint :workouts, name: "workouts_places_array"
    remove_column :workouts, :places
  end

  private

  def replace_action_constraint(actions)
    remove_check_constraint :admin_events, name: "admin_events_action"
    add_check_constraint :admin_events,
                         "action::text = ANY (ARRAY[#{actions.map { |action| "'#{action}'::character varying" }.join(', ')}]::text[])",
                         name: "admin_events_action"
  end
end
