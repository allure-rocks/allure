# frozen_string_literal: true

# One user's gear item with denormalized lifetime totals. Totals are
# maintained by `Equipments::Totals` on associate/dissociate/metric-change
# and repaired by the refresh endpoint; they are never edited directly.
# See PLAN_M3.md sections 6.3 and 7.5.
class Equipment < ApplicationRecord
  include HasShortId

  # `equipment` is uncountable to the inflector; the table is `equipments`.
  self.table_name = "equipments"

  belongs_to :user
  belongs_to :equipment_type
  # Gear synchronised from a remote provider (PLAN_REMOTE_IMPORTS.md §6.3).
  belongs_to :import_connection, optional: true
  has_and_belongs_to_many :workouts, join_table: "workout_equipments"

  validates :uuid, uniqueness: true, allow_nil: true
  validates :label, length: { in: 1..50 }, uniqueness: { scope: :user_id }
  validates :description, length: { maximum: 2_000 }, allow_nil: true
  validates :is_active, inclusion: { in: [ true, false ] }
  validates :total_distance, numericality: { greater_than_or_equal_to: 0 }
  validates :total_duration, :total_moving, :total_workouts,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
