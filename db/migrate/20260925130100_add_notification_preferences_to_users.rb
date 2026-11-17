# frozen_string_literal: true

# Per-account in-app notification preferences (docs/dev/NOTIFICATIONS.md). A
# disabled kind is never created, so re-enabling it does not resurrect old
# events.
class AddNotificationPreferencesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :notify_follow_requests, :boolean, default: true, null: false
    add_column :users, :notify_follow_accepted, :boolean, default: true, null: false
  end
end
