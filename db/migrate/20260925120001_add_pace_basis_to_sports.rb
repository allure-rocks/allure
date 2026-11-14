# frozen_string_literal: true

class AddPaceBasisToSports < ActiveRecord::Migration[8.1]
  def change
    add_column :sports, :pace_basis_metres, :integer

    add_check_constraint :sports,
                         "pace_basis_metres IS NULL OR pace_basis_metres > 0",
                         name: "sports_pace_basis_metres"
  end
end
