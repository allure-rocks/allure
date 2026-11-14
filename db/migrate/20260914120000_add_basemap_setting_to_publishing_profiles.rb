# frozen_string_literal: true

# Every existing publishing profile gains the new "basemap" setting enabled.
# Without the backfill an existing profile would render the checkbox unchecked
# and the first save of the profile form would silently turn the map background
# off for every future publication.
class AddBasemapSettingToPublishingProfiles < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE publishing_profiles
      SET settings = settings || '{"basemap": true}'::jsonb,
          updated_at = CURRENT_TIMESTAMP
      WHERE NOT settings ? 'basemap'
    SQL
  end

  def down
    execute <<~SQL
      UPDATE publishing_profiles
      SET settings = settings - 'basemap',
          updated_at = CURRENT_TIMESTAMP
      WHERE settings ? 'basemap'
    SQL
  end
end
