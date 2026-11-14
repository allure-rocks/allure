# frozen_string_literal: true

# One personal best over a standard distance for a (user, sport), recomputed
# by `Records::RecomputeService` from the user's `best_efforts`. Mirrors
# `Record`: the source workout may be deleted (`workout_id` is nullified and a
# recompute re-points the row to the runner-up). See PLAN_BEST_EFFORTS.md.
class EffortRecord < ApplicationRecord
  belongs_to :user, inverse_of: :effort_records
  belongs_to :sport, inverse_of: :effort_records
  belongs_to :workout, optional: true, inverse_of: :effort_records

  validates :distance_key, presence: true, uniqueness: { scope: %i[user_id sport_id] }
  validates :distance_meters, numericality: { greater_than: 0 }
  validates :duration_seconds, numericality: { only_integer: true, greater_than: 0 }
  validates :workout_started_at, presence: true
end
