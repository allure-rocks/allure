# frozen_string_literal: true

# PLAN_SEGMENTS.md §8.2: a segment board follows its reader and the shared
# route, so the publishing profile's `segment` setting is retired. Frozen
# publication snapshots keep the key, which is ignored.
class RetireSegmentPublishingSetting < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE publishing_profiles SET settings = settings - 'segment' WHERE settings ? 'segment'
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE publishing_profiles SET settings = settings || '{"segment": true}'::jsonb
    SQL
  end
end
