# The release whose notes this account has seen. Null means "never seen": no
# backfill, so existing accounts meet the current release's dialog once, and
# new accounts are marked at creation (User#mark_release_notes_seen).
class AddReleaseNotesSeenVersionToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :release_notes_seen_version, :string
  end
end
