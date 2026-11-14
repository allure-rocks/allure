# frozen_string_literal: true

# A recurring route the owner has not saved yet (PLAN_SEGMENTS.md §7.7).
# Nothing here is a course: the suggestion names the recordings that follow the
# same complete track, and the owner decides whether to save it as a route or
# to dismiss it for good. A dismissed suggestion keeps absorbing later
# recordings of the same circuit, so the owner is never asked twice.
class RouteSuggestion < ApplicationRecord
  STATUSES = %w[pending dismissed accepted].freeze

  belongs_to :user
  belongs_to :sport
  # The recording the route form is built from when the suggestion is accepted.
  # Nullified when that recording is deleted; the newest remaining member then
  # takes its place.
  belongs_to :reference_workout, class_name: "Workout", optional: true
  # The route the owner saved from this suggestion, once accepted.
  belongs_to :segment, optional: true
  has_many :route_suggestion_workouts, dependent: :destroy, inverse_of: :route_suggestion
  has_many :workouts, through: :route_suggestion_workouts

  validates :status, inclusion: { in: STATUSES }
  validate :reference_workout_belongs_to_the_owner
  validate :segment_is_a_route

  scope :pending, -> { where(status: "pending") }
  scope :dismissed, -> { where(status: "dismissed") }
  scope :accepted, -> { where(status: "accepted") }

  def pending? = status == "pending"
  def dismissed? = status == "dismissed"
  def accepted? = status == "accepted"

  # The workout the route form is built from: the reference, or the newest
  # remaining member once the reference is gone. The detector compares a new
  # recording against the same geometry.
  def effective_reference_workout
    reference_workout || Workout.where(id: route_suggestion_workouts.select(:workout_id))
      .order(started_at: :desc, id: :desc)
      .first
  end

  # The most recent recording of the circuit, for the banner's date.
  def latest_started_at
    Workout.where(id: route_suggestion_workouts.select(:workout_id)).maximum(:started_at)
  end

  def occurrences_count
    route_suggestion_workouts.count
  end

  private

  def reference_workout_belongs_to_the_owner
    return if reference_workout.blank? || reference_workout.user_id == user_id

    errors.add(:reference_workout, :invalid)
  end

  def segment_is_a_route
    return if segment.blank? || segment.kind == "route"

    errors.add(:segment, :invalid)
  end
end
