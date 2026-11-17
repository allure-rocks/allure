# frozen_string_literal: true

# One recorded place of a workout, derived from its stored toponymy by
# Workouts::PlaceNamer (docs/dev/WORKOUT.md). The indexable source of the owner's
# place filter and autocomplete: it covers every recorded marker, not just the
# few places the workout displays. Owner-only, never published or federated,
# and never carrying a coordinate.
class WorkoutPlaceName < ApplicationRecord
  belongs_to :workout, inverse_of: :place_names
  belongs_to :user

  validates :name, presence: true, length: { maximum: 120 }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :position, uniqueness: { scope: :workout_id }
end
