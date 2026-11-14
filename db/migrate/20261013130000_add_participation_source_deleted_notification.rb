# frozen_string_literal: true

# PLAN_TOGETHER.md §6.5, §9: the participant learns that the source of a
# credit they keep was deleted. The confirmations switch governs it, so no
# preference column is added.
class AddParticipationSourceDeletedNotification < ActiveRecord::Migration[8.1]
  PREVIOUS_KINDS = %w[
    follow_request follow_accepted publication_activated reaction
    participation_requested participation_suggested participation_confirmed
    comment import_connection_expired import_connection_revoked
    auto_published auto_publication_failed webhook_disabled
  ].freeze
  ADDED_KIND = "participation_source_deleted"

  def up
    replace_constraint(PREVIOUS_KINDS + [ ADDED_KIND ])
  end

  def down
    execute "DELETE FROM notifications WHERE kind = '#{ADDED_KIND}'"
    replace_constraint(PREVIOUS_KINDS)
  end

  private

  def replace_constraint(kinds)
    remove_check_constraint :notifications, name: "notifications_kind"
    add_check_constraint :notifications, "kind IN (#{kinds.map { "'#{it}'" }.join(', ')})", name: "notifications_kind"
  end
end
