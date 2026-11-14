# frozen_string_literal: true

# PLAN_TOGETHER.md §8, slice 3c: when a credited participant imports their own
# recording of the same outing, detection suggests turning the credit into a
# link. The suggestion lives on the participation (the recording it names,
# nullified if that recording is deleted, and the participant's dismissal),
# and the participant learns of it through a new notice kind under the
# confirmations switch.
class AddLinkSuggestionToParticipations < ActiveRecord::Migration[8.1]
  PREVIOUS_KINDS = %w[
    follow_request follow_accepted publication_activated reaction
    participation_requested participation_suggested participation_confirmed
    participation_source_deleted
    comment import_connection_expired import_connection_revoked
    auto_published auto_publication_failed webhook_disabled
  ].freeze
  ADDED_KIND = "participation_link_suggested"

  def up
    add_reference :workout_participations, :suggested_workout,
                  foreign_key: { to_table: :workouts, on_delete: :nullify }
    add_column :workout_participations, :link_suggestion_dismissed_at, :datetime
    add_check_constraint :workout_participations,
                         "suggested_workout_id IS NULL OR kind = 'credit'",
                         name: "workout_participations_suggestion_is_credit"
    replace_kinds(PREVIOUS_KINDS + [ ADDED_KIND ])
  end

  def down
    execute "DELETE FROM notifications WHERE kind = '#{ADDED_KIND}'"
    replace_kinds(PREVIOUS_KINDS)
    remove_check_constraint :workout_participations, name: "workout_participations_suggestion_is_credit"
    remove_column :workout_participations, :link_suggestion_dismissed_at
    remove_reference :workout_participations, :suggested_workout, foreign_key: { to_table: :workouts }
  end

  private

  def replace_kinds(kinds)
    remove_check_constraint :notifications, name: "notifications_kind"
    add_check_constraint :notifications, "kind IN (#{kinds.map { "'#{it}'" }.join(', ')})", name: "notifications_kind"
  end
end
