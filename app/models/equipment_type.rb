# frozen_string_literal: true

# A reference equipment category (bike, shoes, …), seeded idempotently like
# the sport catalog. Types are never deleted through the UI; deactivating
# hides a type from new equipment without orphaning existing rows.
class EquipmentType < ApplicationRecord
  has_many :equipments, dependent: :restrict_with_exception

  validates :slug, presence: true, uniqueness: true
  validates :label, presence: true
  validates :is_active, inclusion: { in: [ true, false ] }
end
