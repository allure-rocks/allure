# frozen_string_literal: true

# PLAN_HEART_RATE.md §3.1: an account's heart-rate profile. Without a maximum
# Allure interprets nothing; the bounds are the lower edges of Z2…Z5 in
# percent of the maximum or of the reserve.
class AddHeartRateProfileToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :max_heart_rate, :integer
    add_column :users, :resting_heart_rate, :integer
    add_column :users, :heart_rate_zone_basis, :string, null: false, default: "max"
    add_column :users, :heart_rate_zone_bounds, :integer, array: true, null: false, default: [ 60, 70, 80, 90 ]

    add_check_constraint :users, "max_heart_rate IS NULL OR max_heart_rate BETWEEN 100 AND 220",
                         name: "users_max_heart_rate"
    add_check_constraint :users,
                         "resting_heart_rate IS NULL OR (resting_heart_rate BETWEEN 25 AND 120 AND " \
                         "(max_heart_rate IS NULL OR resting_heart_rate < max_heart_rate))",
                         name: "users_resting_heart_rate"
    add_check_constraint :users, "heart_rate_zone_basis IN ('max', 'reserve')", name: "users_heart_rate_zone_basis"
    add_check_constraint :users, "array_length(heart_rate_zone_bounds, 1) = 4", name: "users_heart_rate_zone_bounds"
  end
end
