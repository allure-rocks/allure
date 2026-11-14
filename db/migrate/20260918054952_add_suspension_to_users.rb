# frozen_string_literal: true

# Account suspension (PLAN_ADMIN.md §7). A suspended account cannot sign in and
# its sessions are revoked; the reason is operator-facing context, never shown
# to the account. Content the account already published stays up: suspension
# revokes access, it does not moderate content.
class AddSuspensionToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :suspended_at, :datetime
    add_column :users, :suspension_reason, :text
  end
end
