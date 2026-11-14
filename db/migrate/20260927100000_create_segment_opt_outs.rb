# frozen_string_literal: true

# PLAN_SEGMENTS.md §6.3: leaderboard participation is opt-out. A row excludes
# one athlete from one segment's board; the absence of a row means the athlete
# is ranked, subject to the eligibility conditions computed on read.
class CreateSegmentOptOuts < ActiveRecord::Migration[8.1]
  def change
    create_table :segment_opt_outs do |t|
      t.references :segment, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end

    add_index :segment_opt_outs, [ :segment_id, :user_id ], unique: true
  end
end
