class AddLeaderboardParticipationToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :leaderboard_participation, :string, null: false, default: "opt_in"
    add_check_constraint :users,
                         "leaderboard_participation IN ('always', 'opt_in', 'never')",
                         name: "users_leaderboard_participation"
  end
end
