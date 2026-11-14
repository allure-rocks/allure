# frozen_string_literal: true

# Existing profiles stored their metric allowlist before grade-adjusted pace
# existed; new profiles pick it up from DEFAULT_SETTINGS. Appending the key
# keeps the per-workout GAP part of the shared representation without forcing
# every owner to edit their profile.
class AddGradeAdjustedPaceToPublishingProfileMetrics < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE publishing_profiles
      SET settings = jsonb_set(settings, '{metrics}', (settings->'metrics') || '["grade_adjusted_pace"]'::jsonb)
      WHERE settings->'metrics' IS NOT NULL
        AND jsonb_typeof(settings->'metrics') = 'array'
        AND NOT (settings->'metrics') @> '["grade_adjusted_pace"]'::jsonb
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE publishing_profiles
      SET settings = jsonb_set(settings, '{metrics}', (settings->'metrics') - 'grade_adjusted_pace')
      WHERE settings->'metrics' IS NOT NULL
        AND jsonb_typeof(settings->'metrics') = 'array'
        AND (settings->'metrics') @> '["grade_adjusted_pace"]'::jsonb
    SQL
  end
end
