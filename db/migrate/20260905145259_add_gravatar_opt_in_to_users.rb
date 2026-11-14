# frozen_string_literal: true

class AddGravatarOptInToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :gravatar_opt_in, :boolean, default: false, null: false
  end
end
