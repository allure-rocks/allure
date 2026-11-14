# frozen_string_literal: true

# PLAN_REMOTE_IMPORTS.md §9: a connected service asking to be linked again.
# `import_connection_revoked` is admitted now so a provider slice only adds its
# producer. One switch governs both kinds.
class AddImportConnectionNotifications < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :notify_import_connections, :boolean, default: true, null: false

    remove_check_constraint :notifications, name: "notifications_kind"
    add_check_constraint :notifications,
                         "kind IN ('follow_request', 'follow_accepted', 'publication_activated', 'reaction', " \
                         "'participation_requested', 'participation_suggested', 'participation_confirmed', 'comment', " \
                         "'import_connection_expired', 'import_connection_revoked')",
                         name: "notifications_kind"
  end

  def down
    remove_check_constraint :notifications, name: "notifications_kind"
    add_check_constraint :notifications,
                         "kind IN ('follow_request', 'follow_accepted', 'publication_activated', 'reaction', " \
                         "'participation_requested', 'participation_suggested', 'participation_confirmed', 'comment')",
                         name: "notifications_kind"

    remove_column :users, :notify_import_connections
  end
end
