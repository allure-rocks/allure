# frozen_string_literal: true

# One index per personal-record winner, so Records::RecomputeService's
# `ORDER BY <metric> LIMIT 1` per (user, sport) is index-backed instead of a
# sort over the account's whole workout history (docs/dev/BEST-EFFORTS.md).
# Concurrent builds keep a deployment from blocking writes on `workouts`.
class AddRecordWinnerIndexesToWorkouts < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEXES = [
    { name: "index_workouts_on_user_sport_average_pace",
      columns: [ :user_id, :sport_id, :average_pace ], where: "average_pace IS NOT NULL" },
    { name: "index_workouts_on_user_sport_average_speed",
      columns: [ :user_id, :sport_id, :average_speed ] },
    { name: "index_workouts_on_user_sport_best_pace",
      columns: [ :user_id, :sport_id, :best_pace ], where: "best_pace IS NOT NULL" },
    { name: "index_workouts_on_user_sport_distance",
      columns: [ :user_id, :sport_id, :distance ] },
    { name: "index_workouts_on_user_sport_ascent",
      columns: [ :user_id, :sport_id, :ascent ] },
    { name: "index_workouts_on_user_sport_moving_time",
      columns: [ :user_id, :sport_id, :moving_time ] },
    { name: "index_workouts_on_user_sport_max_speed",
      columns: [ :user_id, :sport_id, :max_speed ], where: "max_speed IS NOT NULL" }
  ].freeze

  def up
    INDEXES.each do |declaration|
      name = declaration[:name]
      if index_exists?(:workouts, declaration[:columns], name:) && !index_valid?(name)
        remove_index :workouts, name:, algorithm: :concurrently
      end
      add_index :workouts, declaration[:columns], name:, where: declaration[:where],
                algorithm: :concurrently unless index_valid?(name)
    end
  end

  def down
    INDEXES.reverse_each do |declaration|
      remove_index :workouts, name: declaration[:name], algorithm: :concurrently, if_exists: true
    end
  end

  private

  def index_valid?(name)
    connection.select_value(<<~SQL) == true
      SELECT idx.indisvalid
      FROM pg_index idx
      JOIN pg_class relation ON relation.oid = idx.indexrelid
      WHERE relation.relname = #{connection.quote(name)}
    SQL
  end
end
