# frozen_string_literal: true

# docs/dev/AI.md §7, DESIGN.md §20.3: the workout's figures carry a text block
# under the primary tiles. The owner's own description leads it; the assistant
# summary takes that place when there is no description, and joins it only when
# the account asked for both.
class AddAiSummaryWithDescriptionToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :ai_summary_with_description, :boolean, default: false, null: false
  end
end
