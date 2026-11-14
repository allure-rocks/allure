class AddAnalysisVersionIndexToWorkouts < ActiveRecord::Migration[8.1]
  INDEX_NAME = "index_workouts_on_analysis_version_and_id"

  disable_ddl_transaction!

  def up
    validate_check_constraint :workouts, name: "workouts_analysis_version"
    if index_exists?(:workouts, [ :analysis_version, :id ], name: INDEX_NAME) && !index_valid?
      remove_index :workouts, name: INDEX_NAME, algorithm: :concurrently
    end
    add_index :workouts, [ :analysis_version, :id ], name: INDEX_NAME,
              algorithm: :concurrently unless index_valid?
  end

  def down
    remove_index :workouts, name: INDEX_NAME, algorithm: :concurrently, if_exists: true
  end

  private

  def index_valid?
    connection.select_value(<<~SQL) == true
      SELECT idx.indisvalid
      FROM pg_index idx
      JOIN pg_class relation ON relation.oid = idx.indexrelid
      WHERE relation.relname = #{connection.quote(INDEX_NAME)}
    SQL
  end
end
