# frozen_string_literal: true

# Explicit per-segment leaderboard participation (PLAN_SEGMENTS.md §8.2): an
# effort is ranked only when its athlete joined the segment. The owner is a
# participant of their own segment and needs no row. No backfill: existing
# listed efforts do not imply consent.
class CreateSegmentParticipations < ActiveRecord::Migration[8.1]
  def change
    create_table :segment_participations do |t|
      t.references :segment, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end

    add_index :segment_participations, [ :segment_id, :user_id ], unique: true
  end
end
