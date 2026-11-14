class AddLeaderboardCategoryToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :leaderboard_category, :string, null: false, default: "unspecified"
    add_check_constraint :users,
                         "leaderboard_category IN ('unspecified', 'women', 'men')",
                         name: "users_leaderboard_category"
  end
end
