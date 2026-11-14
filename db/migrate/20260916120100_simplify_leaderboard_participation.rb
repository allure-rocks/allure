# frozen_string_literal: true

# The three-value participation setting promised a per-segment opt-in that never
# shipped: the code only ever treated `never` as a gate. It collapses to two
# clear choices — show results, or never — with the new default preserving the
# former behaviour (`opt_in` listed exactly like `always`).
class SimplifyLeaderboardParticipation < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE users SET leaderboard_participation = 'always' WHERE leaderboard_participation = 'opt_in'"

    change_column_default :users, :leaderboard_participation, from: "opt_in", to: "always"
    remove_check_constraint :users, name: "users_leaderboard_participation"
    add_check_constraint :users,
                         "leaderboard_participation IN ('always', 'never')",
                         name: "users_leaderboard_participation"
  end

  def down
    remove_check_constraint :users, name: "users_leaderboard_participation"
    add_check_constraint :users,
                         "leaderboard_participation IN ('always', 'opt_in', 'never')",
                         name: "users_leaderboard_participation"
    change_column_default :users, :leaderboard_participation, from: "always", to: "opt_in"
  end
end
