# frozen_string_literal: true

# Historical weather along a workout (docs/dev/WEATHER.md): one row per
# workout, the provider's raw hourly arrays kept so a new analysis generation
# converges offline, and the account's explicit consent, off for everyone.
class CreateWorkoutWeathers < ActiveRecord::Migration[8.1]
  def change
    create_table :workout_weathers do |t|
      t.references :workout, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string :status, null: false, default: "pending"
      t.integer :fetch_version, null: false, default: 0
      t.integer :analysis_version, null: false, default: 0
      t.string :endpoint
      t.jsonb :samples, null: false, default: []
      t.jsonb :responses, null: false, default: []
      t.jsonb :series, null: false, default: []
      t.jsonb :exposure, null: false, default: {}
      t.jsonb :summary, null: false, default: {}
      t.integer :requests_count, null: false, default: 0
      t.datetime :fetched_at
      t.string :unavailable_reason
      t.string :last_error
      t.timestamps

      t.index :fetched_at
      t.check_constraint "status IN ('pending', 'ready', 'unavailable', 'failed')", name: "workout_weathers_status"
      t.check_constraint "endpoint IS NULL OR endpoint IN ('forecast', 'archive')", name: "workout_weathers_endpoint"
      t.check_constraint "fetch_version >= 0 AND analysis_version >= 0 AND requests_count >= 0",
                         name: "workout_weathers_counters"
      t.check_constraint "jsonb_typeof(samples) = 'array' AND jsonb_typeof(responses) = 'array' " \
                         "AND jsonb_typeof(series) = 'array'",
                         name: "workout_weathers_arrays"
      t.check_constraint "jsonb_typeof(exposure) = 'object' AND jsonb_typeof(summary) = 'object'",
                         name: "workout_weathers_objects"
    end

    add_column :users, :weather_enrichment_enabled, :boolean, null: false, default: false
  end
end
