# frozen_string_literal: true

# docs/dev/PEOPLE.md: a dismissed suggestion never returns for that account.
# The row is owner-scoped and names the suggested actor, so a later suggestion
# pass reads the dismissal without touching the relationship itself.
class CreatePeopleSuggestionDismissals < ActiveRecord::Migration[8.1]
  def change
    create_table :people_suggestion_dismissals do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :actor, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps

      t.index %i[user_id actor_id], unique: true
    end
  end
end
