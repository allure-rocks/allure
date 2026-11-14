# frozen_string_literal: true

# One shared activity between a source workout and another account
# (PLAN_TOGETHER.md). A `credit` means the participant has no recording of
# their own and the source workout counts for them; a `link` names the
# participant's own recording of the same activity, and nothing is counted
# twice. Confirmation is mutual and derived from the two timestamps, so no
# status column can drift. A refusal is terminal for that account on that
# workout: the row stays as history, and only a withdrawal frees the pair.
class WorkoutParticipation < ApplicationRecord
  KINDS = %w[credit link].freeze
  ORIGINS = %w[invitation detection].freeze

  belongs_to :workout, inverse_of: :workout_participations
  belongs_to :participant_actor, class_name: "Actor", inverse_of: :workout_participations
  belongs_to :participant_workout, class_name: "Workout", optional: true, inverse_of: :participant_links
  # A credit's participant appears to have recorded the outing too: detection
  # suggests converting the credit into a link to this recording
  # (PLAN_TOGETHER.md §8). Nullified if the recording is deleted.
  belongs_to :suggested_workout, class_name: "Workout", optional: true
  # The publication a remote participant's `Invite` rides on (PLAN_TOGETHER.md
  # §7); nil for a local participant.
  belongs_to :workout_publication, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :origin, inclusion: { in: ORIGINS }
  validate :link_names_a_recording
  validate :detection_is_a_link
  validate :participant_is_not_the_owner
  validate :recording_belongs_to_the_participant

  # Live rows are neither withdrawn nor declined; a declined row is live on
  # purpose, so the unique pair index blocks a re-invitation.
  scope :live, -> { where(withdrawn_at: nil) }
  scope :active, -> { where(declined_at: nil, withdrawn_at: nil) }
  scope :pending, -> {
    active.where(owner_confirmed_at: nil).or(active.where(participant_confirmed_at: nil))
  }
  scope :confirmed, -> { active.where.not(owner_confirmed_at: nil).where.not(participant_confirmed_at: nil) }
  scope :credits, -> { where(kind: "credit") }
  scope :links, -> { where(kind: "link") }

  def active? = declined_at.nil? && withdrawn_at.nil?
  def declined? = declined_at.present?
  def withdrawn? = withdrawn_at.present?
  # Both confirmations are required; a detection starts with neither.
  def confirmed? = active? && owner_confirmed_at.present? && participant_confirmed_at.present?

  def participant_user = participant_actor&.user

  # A suggestion the participant has neither followed nor dismissed.
  def link_suggestion_open?
    active? && kind == "credit" && suggested_workout_id.present? && link_suggestion_dismissed_at.nil?
  end

  # The participant's credit row for this source, while attached
  # (PLAN_TOGETHER.md §3.2).
  def credit_row
    user = participant_user
    return unless user && kind == "credit"

    workout.credit_rows.find_by(user:)
  end

  private

  # Resolves the association, not the raw id: an unsaved recording has no
  # foreign key yet when a caller builds the row through the association.
  def link_names_a_recording
    errors.add(:participant_workout, :invalid) unless (kind == "link") == participant_workout.present?
  end

  def detection_is_a_link
    errors.add(:kind, :invalid) if origin == "detection" && kind != "link"
  end

  def participant_is_not_the_owner
    return if participant_actor.blank? || workout.blank?

    errors.add(:participant_actor, :invalid) if participant_actor.user_id.present? && participant_actor.user_id == workout.user_id
  end

  def recording_belongs_to_the_participant
    return if participant_workout.blank? || participant_actor.blank?

    errors.add(:participant_workout, :invalid) if participant_workout_id == workout_id
    errors.add(:participant_workout, :invalid) if participant_workout.user_id != participant_actor.user_id
  end
end
