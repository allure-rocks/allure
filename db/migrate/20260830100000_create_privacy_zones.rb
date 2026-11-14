# frozen_string_literal: true

class CreatePrivacyZones < ActiveRecord::Migration[8.1]
  def change
    create_table :privacy_zones do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.string :name
      t.st_point :center, geographic: true, null: false
      t.integer :radius_meters, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :privacy_zones, [ :user_id, :active ], name: "index_privacy_zones_on_user_and_active"
    add_index :privacy_zones, :center, using: :gist
    add_check_constraint :privacy_zones,
                         "radius_meters BETWEEN 1 AND 10000",
                         name: "privacy_zones_radius_meters"
    add_check_constraint :privacy_zones,
                         "char_length(name) <= 120",
                         name: "privacy_zones_name_length"
    add_check_constraint :privacy_zones,
                         "ST_SRID(center::geometry) = 4326 AND ST_GeometryType(center::geometry) = 'ST_Point' AND ST_X(center::geometry) BETWEEN -180 AND 180 AND ST_Y(center::geometry) BETWEEN -90 AND 90",
                         name: "privacy_zones_center"
  end
end
