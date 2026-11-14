# frozen_string_literal: true

class CreateWorkouts < ActiveRecord::Migration[8.1]
  def change
    create_table :workouts do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.references :user, null: false, foreign_key: true, index: false
      t.references :sport, null: false, foreign_key: true

      t.string :title
      t.text :description
      t.text :notes
      t.datetime :started_at, null: false

      t.integer :duration, null: false
      t.integer :moving_time, null: false
      t.integer :pause_time, null: false
      t.decimal :distance, precision: 14, scale: 3, null: false
      t.decimal :ascent, precision: 12, scale: 2, null: false
      t.decimal :descent, precision: 12, scale: 2, null: false
      t.decimal :min_elevation, precision: 10, scale: 2
      t.decimal :max_elevation, precision: 10, scale: 2
      t.decimal :average_speed, precision: 10, scale: 4, null: false
      t.decimal :max_speed, precision: 10, scale: 4
      t.integer :average_pace
      t.integer :best_pace

      t.integer :average_heart_rate
      t.integer :max_heart_rate
      t.integer :average_cadence
      t.integer :max_cadence
      t.integer :average_power
      t.integer :max_power
      t.integer :calories

      t.st_point :start_point, geographic: true, null: false
      t.float :bounds, array: true, null: false

      t.string :workout_visibility, null: false, default: "private"
      t.string :analysis_visibility, null: false, default: "private"
      t.string :map_visibility, null: false, default: "private"
      t.string :media_visibility, null: false, default: "private"

      t.string :source
      t.string :import_format, null: false
      t.integer :points_count, null: false

      t.jsonb :weather_start
      t.jsonb :weather_end
      t.string :federation_state, null: false, default: "draft"
      t.datetime :published_at

      t.timestamps
    end

    add_index :workouts, :uuid, unique: true
    add_index :workouts, [ :user_id, :started_at ], order: { started_at: :desc }
    add_index :workouts, [ :workout_visibility, :started_at ], order: { started_at: :desc }
    add_index :workouts, :start_point, using: :gist

    add_check_constraint :workouts, "duration >= 0", name: "workouts_duration"
    add_check_constraint :workouts, "moving_time >= 0 AND moving_time <= duration", name: "workouts_moving_time"
    add_check_constraint :workouts, "pause_time = duration - moving_time", name: "workouts_pause_time"
    add_check_constraint :workouts,
                         "distance >= 0 AND ascent >= 0 AND descent >= 0 AND average_speed >= 0",
                         name: "workouts_non_negative_metrics"
    add_check_constraint :workouts, "max_speed IS NULL OR max_speed >= 0", name: "workouts_max_speed"
    add_check_constraint :workouts,
                         "average_pace IS NULL OR average_pace >= 0",
                         name: "workouts_average_pace"
    add_check_constraint :workouts, "best_pace IS NULL OR best_pace >= 0", name: "workouts_best_pace"
    add_check_constraint :workouts, "calories IS NULL OR calories >= 0", name: "workouts_calories"
    add_check_constraint :workouts,
                         <<~SQL.squish,
                           (average_heart_rate IS NULL OR average_heart_rate >= 0)
                           AND (max_heart_rate IS NULL OR max_heart_rate >= 0)
                           AND (average_cadence IS NULL OR average_cadence >= 0)
                           AND (max_cadence IS NULL OR max_cadence >= 0)
                           AND (average_power IS NULL OR average_power >= 0)
                           AND (max_power IS NULL OR max_power >= 0)
                         SQL
                         name: "workouts_physiological_metrics"
    add_check_constraint :workouts, "points_count >= 2", name: "workouts_points_count"
    add_check_constraint :workouts, "cardinality(bounds) = 4", name: "workouts_bounds"
    add_check_constraint :workouts, "char_length(title) <= 255", name: "workouts_title_length"
    add_check_constraint :workouts,
                         "char_length(description) <= 10000",
                         name: "workouts_description_length"
    add_check_constraint :workouts, "char_length(notes) <= 500", name: "workouts_notes_length"
    add_check_constraint :workouts, "import_format = 'gpx'", name: "workouts_import_format"
    add_check_constraint :workouts,
                         "federation_state IN ('draft', 'local_only', 'published', 'federated', 'suppress')",
                         name: "workouts_federation_state"

    %i[workout_visibility analysis_visibility map_visibility media_visibility].each do |column|
      add_check_constraint :workouts,
                           "#{column} IN ('public', 'followers_only', 'private')",
                           name: "workouts_#{column}"
    end
  end
end
