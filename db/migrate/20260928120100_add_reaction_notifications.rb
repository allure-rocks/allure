# frozen_string_literal: true

# PLAN_REACTIONS.md: the reaction notice. The kind list is a checked constraint
# in the database (docs/dev/NOTIFICATIONS.md), so the new kind must be admitted
# here, not only in Notification::KINDS. The per-account preference follows the
# existing `notify_*` boolean column convention.
class AddReactionNotifications < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :notify_reactions, :boolean, default: true, null: false

    remove_check_constraint :notifications, name: "notifications_kind"
    add_check_constraint :notifications,
                         "kind IN ('follow_request', 'follow_accepted', 'publication_activated', 'reaction')",
                         name: "notifications_kind"
  end

  def down
    remove_check_constraint :notifications, name: "notifications_kind"
    add_check_constraint :notifications,
                         "kind IN ('follow_request', 'follow_accepted', 'publication_activated')",
                         name: "notifications_kind"

    remove_column :users, :notify_reactions
  end
end
