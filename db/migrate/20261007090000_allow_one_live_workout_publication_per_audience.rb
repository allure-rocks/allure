# frozen_string_literal: true

# A workout carries at most one live (active or scheduled) publication per
# audience instead of one in total (PLAN_AUDIENCES.md §2). The audience is
# derived from the frozen profile snapshot, so it can never disagree with it.
class AllowOneLiveWorkoutPublicationPerAudience < ActiveRecord::Migration[8.1]
  def up
    add_column :workout_publications, :audience, :virtual,
               type: :string, as: "(profile_snapshot ->> 'audience')", stored: true

    remove_index :workout_publications, name: "index_live_workout_publications_on_workout_id"
    add_index :workout_publications, %i[workout_id audience],
              unique: true,
              where: "status IN ('active', 'scheduled')",
              name: "index_live_workout_publications_on_workout_and_audience"
  end

  def down
    remove_index :workout_publications, name: "index_live_workout_publications_on_workout_and_audience"
    add_index :workout_publications, :workout_id,
              unique: true,
              where: "status IN ('active', 'scheduled')",
              name: "index_live_workout_publications_on_workout_id"
    remove_column :workout_publications, :audience
  end
end
