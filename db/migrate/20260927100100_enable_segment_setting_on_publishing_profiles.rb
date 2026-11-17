# frozen_string_literal: true

# docs/dev/SEGMENTS.md: the publishing profile's `segment` setting is the
# athlete's general consent to appear on segment leaderboards. It defaults to
# on, so every existing profile gains it explicitly; profiles created later get
# it from PublishingProfile::DEFAULT_SETTINGS. Existing publications keep the
# policy they were published under — their snapshots are aligned separately.
class EnableSegmentSettingOnPublishingProfiles < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE publishing_profiles
      SET settings = settings || '{"segment": true}'::jsonb
      WHERE settings -> 'segment' IS NULL
    SQL
  end

  def down
    # One-way data migration: a key removed here could have been set by the
    # profile owner afterwards. The explicit setting is harmless if kept.
  end
end
