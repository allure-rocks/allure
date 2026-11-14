# frozen_string_literal: true

# One recording of a recurring-route suggestion (PLAN_SEGMENTS.md §7.7). A
# recording belongs to one suggestion only, and the row is derived: deleting
# the workout removes it, and a suggestion left without a member disappears.
class RouteSuggestionWorkout < ApplicationRecord
  belongs_to :route_suggestion, inverse_of: :route_suggestion_workouts
  belongs_to :workout, inverse_of: :route_suggestion_workouts

  validates :workout_id, uniqueness: true
  validate :workout_belongs_to_the_owner

  after_destroy_commit :destroy_empty_suggestion

  private

  def workout_belongs_to_the_owner
    return if workout.blank? || route_suggestion.blank?
    return if workout.user_id == route_suggestion.user_id

    errors.add(:workout, :invalid)
  end

  # Deleting a recording never leaves an empty suggestion behind. The
  # suggestion's reference is nullified by the foreign key; the banner falls
  # back to the newest remaining member.
  def destroy_empty_suggestion
    RouteSuggestion.where(id: route_suggestion_id)
      .where.missing(:route_suggestion_workouts)
      .destroy_all
  end
end
