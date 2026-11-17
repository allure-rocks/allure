# frozen_string_literal: true

# docs/dev/WORKOUT.md: the analyzer flags readings that look wrong in the
# original file (GPS, timestamps, heart rate, elevation, power, cadence). The
# findings are owner-only derived data, rebuilt with every analysis and never
# part of a publication snapshot.
class AddDataAnomaliesToWorkouts < ActiveRecord::Migration[8.1]
  def change
    add_column :workouts, :data_anomalies, :jsonb, default: {}, null: false
  end
end
