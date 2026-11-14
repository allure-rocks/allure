# frozen_string_literal: true

# An invitation a local account received from a remote Allure owner to confirm
# it took part in a publication it holds (PLAN_TOGETHER.md §3.3, §7). It names
# the received note and the `Invite` that carried it; its answer is a
# confirmation or a refusal, and either side may withdraw it later. A refusal
# stays live, so the same publication is never offered again; a withdrawal
# frees the pair. Never federated back except through its answers.
class RemoteParticipation < ApplicationRecord
  include HasShortId

  belongs_to :remote_note
  belongs_to :recipient_actor, class_name: "Actor"
  # The account's credit row once it confirmed (PLAN_TOGETHER.md §7).
  has_one :credit_row, class_name: "Workout", inverse_of: :remote_participation

  validates :object_uri, :invite_activity_uri, presence: true
  validates :sport_slug, length: { maximum: 64 }, allow_nil: true
  validate :one_answer

  scope :live, -> { where(withdrawn_at: nil) }
  scope :active, -> { live.where(declined_at: nil) }
  scope :pending, -> { active.where(confirmed_at: nil) }
  scope :confirmed, -> { active.where.not(confirmed_at: nil) }

  def active? = withdrawn_at.nil? && declined_at.nil?
  def pending? = active? && confirmed_at.nil?
  def confirmed? = active? && confirmed_at.present?
  def declined? = declined_at.present?
  def withdrawn? = withdrawn_at.present?

  def recipient_user = recipient_actor&.user
  # The owner who invited: the note's author.
  def origin_actor = remote_note&.actor

  private

  def one_answer
    errors.add(:declined_at, :invalid) if confirmed_at.present? && declined_at.present?
  end
end
