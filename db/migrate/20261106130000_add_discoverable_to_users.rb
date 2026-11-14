# frozen_string_literal: true

# PLAN_PEOPLE.md §2: whether an account may be found by name search and
# suggestions. `none` is the default for every account, existing and new, so
# the directory starts empty and a member opts in explicitly. An exact handle
# still reaches a hidden account: following needs it.
class AddDiscoverableToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :discoverable, :string, default: "none", null: false
    add_check_constraint :users, "discoverable IN ('none', 'members')", name: "users_discoverable"
    add_index :users, :discoverable, where: "discoverable = 'members'", name: "index_users_on_discoverable_members"
  end
end
