class AddPublicationActorAndSourceRetention < ActiveRecord::Migration[8.1]
  def up
    add_reference :workout_publications,
                  :actor,
                  null: true,
                  foreign_key: { to_table: :actors },
                  index: true

    execute <<~SQL
      UPDATE workout_publications
      SET actor_id = (
        SELECT actors.id
        FROM actors
        INNER JOIN workouts ON workouts.user_id = actors.user_id
        WHERE workouts.id = workout_publications.workout_id
          AND actors.local = TRUE
        LIMIT 1
      )
      WHERE actor_id IS NULL
    SQL

    change_column_null :workout_publications, :actor_id, false

    change_column_null :workout_publications, :workout_id, true
    remove_foreign_key :workout_publications, column: :workout_id
    add_foreign_key :workout_publications, :workouts, column: :workout_id, on_delete: :nullify
    add_check_constraint :workout_publications,
                         "status = 'deleted' OR workout_id IS NOT NULL",
                         name: "workout_publications_active_requires_source"
  end

  def down
    remove_check_constraint :workout_publications, name: "workout_publications_active_requires_source"
    remove_foreign_key :workout_publications, column: :workout_id
    change_column_null :workout_publications, :workout_id, false
    add_foreign_key :workout_publications, :workouts, column: :workout_id
    remove_reference :workout_publications, :actor, foreign_key: { to_table: :actors }
  end
end
