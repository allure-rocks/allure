# frozen_string_literal: true

# The global participation preference is superseded by the explicit per-segment
# opt-in (docs/dev/SEGMENTS.md). Values are discarded, not migrated: joining a
# segment is now the only way to appear on its board.
class DropLeaderboardParticipationFromUsers < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :users, name: "users_leaderboard_participation"
    remove_column :users, :leaderboard_participation
  end

  def down
    add_column :users, :leaderboard_participation, :string, default: "always", null: false
    add_check_constraint :users,
                         "leaderboard_participation IN ('always', 'never')",
                         name: "users_leaderboard_participation"
  end
end
