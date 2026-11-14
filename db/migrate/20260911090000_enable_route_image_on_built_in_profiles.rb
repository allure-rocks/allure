# frozen_string_literal: true

# Built-in profiles follow the application default for the sanitized route
# image: it is now included so every publication card carries the PNG. Only
# built-in rows are touched; custom profiles keep exactly what their owner
# configured.
class EnableRouteImageOnBuiltInProfiles < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE publishing_profiles
      SET settings = settings || '{"route_image": true}'::jsonb,
          updated_at = CURRENT_TIMESTAMP
      WHERE built_in_key IS NOT NULL
        AND settings->>'route_image' = 'false'
    SQL
  end

  # Intentionally one-way: reverting would silently turn a sharing setting
  # back off for profiles whose owners may have enabled it themselves.
  def down; end
end
