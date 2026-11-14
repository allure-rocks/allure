# frozen_string_literal: true

# PLAN_HEART_RATE.md §3.3–§3.4: one seconds-per-bpm histogram per recording,
# with the zone seconds and load it gives under the account's current zones.
class CreateWorkoutHeartRates < ActiveRecord::Migration[8.1]
  def change
    create_table :workout_heart_rates do |t|
      t.references :workout, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.integer :version, null: false
      t.integer :histogram, array: true, null: false
      t.integer :sampled_seconds, null: false
      t.integer :recorded_seconds, null: false
      t.integer :zone_seconds, array: true
      t.decimal :load, precision: 8, scale: 1
      t.string :zones_fingerprint
      t.timestamps

      t.check_constraint "array_length(histogram, 1) = 191", name: "workout_heart_rates_histogram"
      t.check_constraint "sampled_seconds >= 0 AND recorded_seconds >= 0", name: "workout_heart_rates_seconds"
      t.check_constraint "zone_seconds IS NULL OR array_length(zone_seconds, 1) = 5",
                         name: "workout_heart_rates_zone_seconds"
      t.check_constraint "(zone_seconds IS NULL) = (zones_fingerprint IS NULL) AND " \
                         "(load IS NULL OR zones_fingerprint IS NOT NULL)",
                         name: "workout_heart_rates_zones"
      t.check_constraint "load IS NULL OR load >= 0", name: "workout_heart_rates_load"
    end

    add_column :workouts, :heart_rate_version, :integer, null: false, default: 0
  end
end
