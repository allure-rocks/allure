class AddWeekStartToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :week_start, :string, null: false, default: "monday"
    add_check_constraint :users,
                         "week_start IN ('monday', 'sunday')",
                         name: "users_week_start"
  end
end
