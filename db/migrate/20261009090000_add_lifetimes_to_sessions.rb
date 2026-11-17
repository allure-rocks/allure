# frozen_string_literal: true

# Session hardening (docs/dev/AUTH.md): a session expires after an idle
# period and an absolute lifetime, and sensitive actions read the last time its
# owner proved their identity. Existing rows take their last update as their
# last activity; none counts as recently re-authenticated.
class AddLifetimesToSessions < ActiveRecord::Migration[8.1]
  def up
    add_column :sessions, :last_seen_at, :datetime
    add_column :sessions, :reauthenticated_at, :datetime
    execute "UPDATE sessions SET last_seen_at = updated_at"
    change_column_null :sessions, :last_seen_at, false
    change_column_default :sessions, :last_seen_at, -> { "CURRENT_TIMESTAMP" }
  end

  def down
    remove_column :sessions, :reauthenticated_at
    remove_column :sessions, :last_seen_at
  end
end
