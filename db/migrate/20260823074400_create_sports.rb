# frozen_string_literal: true

class CreateSports < ActiveRecord::Migration[8.1]
  def change
    create_table :sports do |t|
      t.string :slug, null: false
      t.string :label, null: false
      t.string :colour_group, null: false
      t.boolean :active, null: false, default: true
      t.decimal :stopped_speed_threshold, precision: 5, scale: 2, null: false
      t.string :pace_speed_display, null: false
      t.string :cadence_unit
      t.boolean :records_elevation, null: false, default: true
      t.boolean :records_power, null: false, default: false
      t.integer :position, null: false

      t.timestamps
    end

    add_index :sports, :slug, unique: true
    add_index :sports, :label, unique: true
    add_index :sports, :position, unique: true

    add_check_constraint :sports,
                         "colour_group IN ('run', 'ride', 'hike', 'swim', 'ski', 'other')",
                         name: "sports_colour_group"
    add_check_constraint :sports,
                         "pace_speed_display IN ('pace', 'speed', 'pace_and_speed')",
                         name: "sports_pace_speed_display"
    add_check_constraint :sports,
                         "cadence_unit IS NULL OR cadence_unit IN ('rpm', 'spm')",
                         name: "sports_cadence_unit"
    add_check_constraint :sports,
                         "stopped_speed_threshold >= 0",
                         name: "sports_stopped_speed_threshold"
    add_check_constraint :sports,
                         "slug ~ '\\A[a-z][a-z0-9_]*\\Z'",
                         name: "sports_slug_format"
    add_check_constraint :sports, "position > 0", name: "sports_position"
  end
end
