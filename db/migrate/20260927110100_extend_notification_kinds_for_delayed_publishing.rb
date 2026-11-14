# frozen_string_literal: true

# PLAN_DELAYED_PUBLISHING.md §6: the activation notice. The kind list is a
# checked constraint in the database (PLAN_NOTIFICATIONS.md §2), so the new
# kind must be admitted here, not only in Notification::KINDS.
class ExtendNotificationKindsForDelayedPublishing < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :notifications, name: "notifications_kind"
    add_check_constraint :notifications,
                         "kind IN ('follow_request', 'follow_accepted', 'publication_activated')",
                         name: "notifications_kind"
  end

  def down
    remove_check_constraint :notifications, name: "notifications_kind"
    add_check_constraint :notifications,
                         "kind IN ('follow_request', 'follow_accepted')",
                         name: "notifications_kind"
  end
end
