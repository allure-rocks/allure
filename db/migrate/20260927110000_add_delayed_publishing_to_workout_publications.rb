# frozen_string_literal: true

# PLAN_DELAYED_PUBLISHING.md Slice 1. A `scheduled` publication is a frozen
# sanitized snapshot that is not yet shared: it is invisible locally and carries
# no outbox activity until activation. `published_at` keeps its NOT NULL
# semantics — for a scheduled row it holds the planned moment, and activation
# rewrites it to the actual instant, the controlled immutability exception
# documented on WorkoutPublication#activate!.
#
# The one-live-publication index widens from `active` to `active OR scheduled`,
# so a workout can never hold two pending representations. The delay is a
# profile policy column, not a snapshot setting: existing representations are
# byte-identical and no federated payload changes.
class AddDelayedPublishingToWorkoutPublications < ActiveRecord::Migration[8.1]
  DELAY_VALUES = [ 86_400, 259_200, 604_800, 1_209_600, 2_592_000 ].freeze

  def up
    add_column :workout_publications, :scheduled_for, :datetime

    remove_check_constraint :workout_publications, name: "workout_publications_status"
    add_check_constraint :workout_publications,
                         "status IN ('active', 'scheduled', 'deleted')",
                         name: "workout_publications_status"

    remove_check_constraint :workout_publications, name: "workout_publications_deletion_state"
    add_check_constraint :workout_publications,
                         "status IN ('active', 'scheduled') AND deleted_at IS NULL OR " \
                         "status = 'deleted' AND deleted_at IS NOT NULL",
                         name: "workout_publications_deletion_state"

    add_check_constraint :workout_publications,
                         "status <> 'scheduled' OR scheduled_for IS NOT NULL",
                         name: "workout_publications_scheduled_for"

    remove_index :workout_publications, name: "index_active_workout_publications_on_workout_id"
    add_index :workout_publications, :workout_id,
              unique: true,
              where: "status IN ('active', 'scheduled')",
              name: "index_live_workout_publications_on_workout_id"
    add_index :workout_publications, :scheduled_for,
              where: "status = 'scheduled'",
              name: "index_workout_publications_on_scheduled_for"

    add_column :publishing_profiles, :publish_delay_seconds, :integer, default: 86_400, null: false
    add_check_constraint :publishing_profiles,
                         "publish_delay_seconds IN (#{DELAY_VALUES.join(', ')})",
                         name: "publishing_profiles_publish_delay_seconds"

    add_column :users, :notify_publication_activated, :boolean, default: true, null: false
  end

  def down
    remove_column :users, :notify_publication_activated

    remove_check_constraint :publishing_profiles, name: "publishing_profiles_publish_delay_seconds"
    remove_column :publishing_profiles, :publish_delay_seconds

    remove_index :workout_publications, name: "index_workout_publications_on_scheduled_for"
    remove_index :workout_publications, name: "index_live_workout_publications_on_workout_id"
    add_index :workout_publications, :workout_id,
              unique: true,
              where: "status = 'active'",
              name: "index_active_workout_publications_on_workout_id"

    remove_check_constraint :workout_publications, name: "workout_publications_scheduled_for"
    remove_check_constraint :workout_publications, name: "workout_publications_deletion_state"
    add_check_constraint :workout_publications,
                         "status = 'active' AND deleted_at IS NULL OR " \
                         "status = 'deleted' AND deleted_at IS NOT NULL",
                         name: "workout_publications_deletion_state"
    remove_check_constraint :workout_publications, name: "workout_publications_status"
    add_check_constraint :workout_publications,
                         "status IN ('active', 'deleted')",
                         name: "workout_publications_status"

    remove_column :workout_publications, :scheduled_for
  end
end
