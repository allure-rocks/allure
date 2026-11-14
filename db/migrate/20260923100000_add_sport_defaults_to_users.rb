# frozen_string_literal: true

# Per-account sport defaults: when an import detects one of the generic sports
# (`cycling`, `running`, `walking`), the owner's preferred variant of the same
# icon family is used instead. Nil keeps the detected generic sport.
class AddSportDefaultsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :default_cycling_sport,
                  foreign_key: { to_table: :sports, on_delete: :nullify }
    add_reference :users, :default_running_sport,
                  foreign_key: { to_table: :sports, on_delete: :nullify }
    add_reference :users, :default_walking_sport,
                  foreign_key: { to_table: :sports, on_delete: :nullify }
  end
end
