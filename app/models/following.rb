# frozen_string_literal: true

require "uri"

class Following < ApplicationRecord
  STATUSES = %w[pending accepted rejected undone].freeze
  ACTIVE_STATUSES = STATUSES - [ "undone" ]

  belongs_to :follower_actor, class_name: "Actor", inverse_of: :outgoing_followings
  belongs_to :followed_actor, class_name: "Actor", inverse_of: :incoming_followings

  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :accepted, -> { where(status: "accepted") }
  scope :accepted_followers_of, ->(actor) { accepted.where(followed_actor: actor) }
  scope :accepted_following_of, ->(actor) { accepted.where(follower_actor: actor) }
  scope :accepted_between, ->(follower_actor:, followed_actor:) { accepted.where(follower_actor:, followed_actor:) }
  # The local accounts the actor follows (accepted), as a relation selecting
  # their ids: the join through the followed actor's user keeps remote
  # actors (no local account) out.
  scope :local_user_ids_followed_by, ->(actor) {
    accepted_following_of(actor).joins(followed_actor: :user).select("users.id")
  }

  validates :uri, presence: true, uniqueness: true
  validates :follower_actor_id,
            uniqueness: { scope: :followed_actor_id, conditions: -> { where.not(status: "undone") } }
  validates :status, inclusion: { in: STATUSES }
  validates :requested_at, presence: true
  validate :uri_is_absolute
  validate :actors_are_distinct
  validate :status_timestamps

  # Ends every live relationship with these actors, in both directions and
  # locally only: a blocked actor gets nothing delivered and a deleted one
  # has no inbox left.
  def self.end_with!(actors, at: Time.current)
    ids = actors.is_a?(ActiveRecord::Relation) ? actors.select(:id) : Array(actors).map(&:id)
    active.where(follower_actor_id: ids).or(active.where(followed_actor_id: ids)).find_each { it.undo!(at:) }
  end

  def pending? = status == "pending"
  def accepted? = status == "accepted"
  def rejected? = status == "rejected"
  def undone? = status == "undone"
  def active? = ACTIVE_STATUSES.include?(status)

  def eligible_for_follower_access?
    accepted? && !follower_actor.tombstoned? && !followed_actor.tombstoned?
  end

  def accept!(at: Time.current)
    with_lock do
      return self if accepted?
      raise InvalidTransition, "only pending followings can be accepted" unless pending?

      update!(status: "accepted", accepted_at: at, undone_at: nil)
    end
  end

  def reject!(at: Time.current)
    with_lock do
      return self if rejected?
      raise InvalidTransition, "only pending followings can be rejected" unless pending?

      update!(status: "rejected", accepted_at: nil, undone_at: nil)
    end
  end

  def undo!(at: Time.current)
    with_lock do
      return self if undone?

      update!(status: "undone", undone_at: at, accepted_at: nil)
    end
  end

  class InvalidTransition < StandardError; end

  private

  def uri_is_absolute
    parsed = URI.parse(uri.to_s)
    valid = parsed.scheme.in?(%w[http https]) && parsed.host.present? &&
      parsed.userinfo.blank? && parsed.fragment.blank?
    errors.add(:uri, :invalid) unless valid
  rescue URI::InvalidURIError, URI::InvalidComponentError
    errors.add(:uri, :invalid)
  end

  def actors_are_distinct
    errors.add(:followed_actor, :invalid) if follower_actor_id.present? && follower_actor_id == followed_actor_id
  end

  def status_timestamps
    errors.add(:accepted_at, :blank) if accepted? && accepted_at.blank?
    errors.add(:accepted_at, :present) if !accepted? && accepted_at.present?
    errors.add(:undone_at, :blank) if undone? && undone_at.blank?
    errors.add(:undone_at, :present) if !undone? && undone_at.present?
  end
end
