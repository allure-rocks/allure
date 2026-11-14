# frozen_string_literal: true

# PLAN_TOGETHER.md §9: the participation notices. The kind list is a checked
# constraint in the database (PLAN_NOTIFICATIONS.md §2), so the three kinds are
# admitted here, not only in Notification::KINDS. The per-account preferences
# follow the existing `notify_*` boolean column convention: one switch covers
# requests and suggestions, one covers confirmations.
class AddParticipationNotificationKinds < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :notify_participation_requests, :boolean, default: true, null: false
    add_column :users, :notify_participation_confirmed, :boolean, default: true, null: false

    remove_check_constraint :notifications, name: "notifications_kind"
    add_check_constraint :notifications,
                         "kind IN ('follow_request', 'follow_accepted', 'publication_activated', 'reaction', " \
                         "'participation_requested', 'participation_suggested', 'participation_confirmed')",
                         name: "notifications_kind"
  end

  def down
    remove_check_constraint :notifications, name: "notifications_kind"
    add_check_constraint :notifications,
                         "kind IN ('follow_request', 'follow_accepted', 'publication_activated', 'reaction')",
                         name: "notifications_kind"

    remove_column :users, :notify_participation_requests
    remove_column :users, :notify_participation_confirmed
  end
end
