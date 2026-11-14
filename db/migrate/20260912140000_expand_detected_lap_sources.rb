class ExpandDetectedLapSources < ActiveRecord::Migration[8.1]
  SOURCES = %w[loop route pause climb descent stop speed_interval power_interval].freeze

  def up
    remove_check_constraint :detected_laps, name: "detected_laps_source"
    remove_check_constraint :detected_laps, name: "detected_laps_non_negative_metrics"
    add_check_constraint :detected_laps,
                         "source IN (#{SOURCES.map { |source| "'#{source}'" }.join(', ')})",
                         name: "detected_laps_source"
    add_check_constraint :detected_laps,
                         <<~SQL.squish,
                           distance >= 0 AND
                           (ascent IS NULL OR ascent >= 0) AND
                           (descent IS NULL OR descent >= 0) AND
                           (average_speed IS NULL OR average_speed >= 0) AND
                           (max_speed IS NULL OR max_speed >= 0)
                         SQL
                         name: "detected_laps_non_negative_metrics"
    add_column :detected_laps, :max_power, :integer
    add_check_constraint :detected_laps,
                         "max_power IS NULL OR max_power >= 0",
                         name: "detected_laps_max_power"
  end

  def down
    remove_check_constraint :detected_laps, name: "detected_laps_max_power"
    remove_column :detected_laps, :max_power
    remove_check_constraint :detected_laps, name: "detected_laps_source"
    remove_check_constraint :detected_laps, name: "detected_laps_non_negative_metrics"
    add_check_constraint :detected_laps,
                         "source IN ('loop', 'route', 'pause', 'climb')",
                         name: "detected_laps_source"
    add_check_constraint :detected_laps,
                         <<~SQL.squish,
                           distance > 0 AND
                           (ascent IS NULL OR ascent >= 0) AND
                           (descent IS NULL OR descent >= 0) AND
                           (average_speed IS NULL OR average_speed >= 0) AND
                           (max_speed IS NULL OR max_speed >= 0)
                         SQL
                         name: "detected_laps_non_negative_metrics"
  end
end
