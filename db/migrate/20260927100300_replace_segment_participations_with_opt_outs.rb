# frozen_string_literal: true

# PLAN_SEGMENTS.md §6.2/§6.3: eligibility is computed on read from the segment,
# the active publication, the exclusions, and the effort owner's zones, so the
# stored `segment_efforts.listed` snapshot and its refresh machinery are gone.
# Participation becomes opt-out: a `segment_opt_outs` row is the exclusion.
class ReplaceSegmentParticipationsWithOptOuts < ActiveRecord::Migration[8.1]
  def up
    drop_table :segment_participations
    remove_column :segment_efforts, :listed
  end

  def down
    create_table :segment_participations do |t|
      t.references :segment, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end

    add_index :segment_participations, [ :segment_id, :user_id ], unique: true
    add_column :segment_efforts, :listed, :boolean, default: false, null: false
  end
end
