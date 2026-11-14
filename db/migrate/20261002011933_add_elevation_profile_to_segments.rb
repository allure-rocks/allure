class AddElevationProfileToSegments < ActiveRecord::Migration[8.1]
  def change
    add_column :segments, :elevation_profile, :jsonb
  end
end
