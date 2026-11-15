# frozen_string_literal: true

require "securerandom"
require "uri"

class FederationOutboxEvent < ApplicationRecord
  SUBJECT_TYPES = %w[WorkoutPublication SegmentPublication Actor].freeze
  ACTIVITY_TYPES = %w[Create Delete Undo Follow Accept Reject Like Announce Invite].freeze
  STATUSES = %w[preparing pending expanded complete cancelled failed].freeze
  TERMINAL_STATUSES = %w[complete cancelled failed].freeze
  IMMUTABLE_ATTRIBUTES = %i[
    actor_id subject_type subject_id workout_publication_id segment_publication_id
    event_uuid activity_type activity_uri object_uri payload audience
  ].freeze

  belongs_to :actor, inverse_of: :federation_outbox_events
  belongs_to :workout_publication, optional: true, inverse_of: :outbox_events
  belongs_to :segment_publication, optional: true, inverse_of: :outbox_events
  has_many :deliveries, class_name: "FederationDelivery", inverse_of: :outbox_event,
           dependent: :restrict_with_exception

  attr_readonly(*IMMUTABLE_ATTRIBUTES)

  scope :active, -> { where(status: %w[pending expanded]) }
  # Excludes publication Creates whose subject is no longer active, so deleted
  # publications never appear in outbox collections (docs/dev/PUBLISHING.md), and the
  # comment relays riding on them with them (PLAN_COMMENTS.md §9). All other
  # events (Deletes, Undos, Actor activities) pass through.
  scope :live_publication_creates, -> {
    where(
      <<~SQL.squish
        NOT (
          federation_outbox_events.subject_type = 'WorkoutPublication' AND
          federation_outbox_events.activity_type IN ('Create', 'Announce', 'Invite') AND
          COALESCE(federation_outbox_events.workout_publication_id, federation_outbox_events.subject_id) NOT IN (
            SELECT id FROM workout_publications WHERE status = 'active'
          )
        ) AND NOT (
          federation_outbox_events.subject_type = 'SegmentPublication' AND
          federation_outbox_events.activity_type = 'Create' AND
          COALESCE(federation_outbox_events.segment_publication_id, federation_outbox_events.subject_id) NOT IN (
            SELECT id FROM segment_publications WHERE status = 'active'
          )
        )
      SQL
    )
  }

  # A comment's Create, and the host's Announce relaying it, leave the outbox
  # with the comment (PLAN_COMMENTS.md §3.3): a comment deleted, removed, or
  # refused is never served again. An Announce names its comment only inside
  # its payload, which its withdrawal redacts, so it is served only while that
  # comment is still in its thread.
  scope :without_withdrawn_comments, -> {
    where(
      <<~SQL.squish
        NOT EXISTS (
          SELECT 1 FROM comments
          WHERE comments.uri = federation_outbox_events.object_uri
            AND federation_outbox_events.activity_type = 'Create'
            AND comments.status <> 'active'
        ) AND NOT (
          federation_outbox_events.activity_type = 'Announce' AND NOT EXISTS (
            SELECT 1 FROM comments
            WHERE comments.uri = federation_outbox_events.payload -> 'object' ->> 'id'
              AND comments.status = 'active'
          )
        )
      SQL
    )
  }

  before_validation :assign_event_identity, on: :create

  validates :subject_type, inclusion: { in: SUBJECT_TYPES }
  validates :event_uuid, presence: true, uniqueness: true
  validates :activity_type, inclusion: { in: ACTIVITY_TYPES }
  validates :activity_uri, presence: true, uniqueness: true
  validates :object_uri, presence: true
  validates :payload, :audience, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  # Actor currency is an intent invariant, enforced when the event is created.
  # A deletion event must stay updatable after its own actor is tombstoned so
  # its delivery can reach terminal state and the key can retire (docs/dev/FEDERATION.md).
  validate :actor_is_current_local_actor, on: :create
  validate :uris_are_absolute
  validate :payload_and_audience_are_objects
  validate :publication_subject_integrity

  def preparing? = status == "preparing"
  def pending? = status == "pending"
  def expanded? = status == "expanded"
  def terminal? = TERMINAL_STATUSES.include?(status)
  def complete? = status == "complete"
  def cancelled? = status == "cancelled"
  def failed? = status == "failed"

  # `preparing` is the publication Create intent waiting for its route image
  # before federation delivery. Only the render job or stale recovery moves it.
  def mark_pending!
    update_column(:status, "pending") unless status == "pending"
    self
  end

  def mark_expanded!
    update!(status: "expanded") unless expanded? || terminal?
    self
  end

  def mark_complete!
    update!(status: "complete") unless status == "complete"
    self
  end

  def mark_failed!(error:)
    update!(status: "failed", last_error: error.to_s.gsub(/\s+/, " ").truncate(500))
    self
  end

  def mark_cancelled!(reason:)
    update!(status: "cancelled", last_error: reason.to_s.gsub(/\s+/, " ").truncate(500))
    self
  end

  # Deterministic parent projection used by delivery and recovery. Returns true
  # when the event reached a terminal status. Terminal events are never moved.
  # Pending events without deliveries stay pending for expansion.
  def reconcile_terminal_status!
    return true if terminal?
    return false unless status.in?(%w[pending expanded])
    return false if status == "pending" && !deliveries.exists?

    if deliveries.exists?
      return false unless deliveries.all?(&:terminal?)

      if deliveries.any? { |delivery| delivery.status == "failed" }
        mark_failed!(error: "one or more deliveries failed")
      else
        mark_complete!
      end
    else
      mark_complete!
    end
    true
  end

  private

  def assign_event_identity
    self.event_uuid ||= SecureRandom.uuid
    self.activity_uri ||= "#{object_uri}/activities/#{event_uuid}" if object_uri.present?
  end

  def actor_is_current_local_actor
    errors.add(:actor, :invalid) unless actor&.local? && !actor.tombstoned?
  end

  def uris_are_absolute
    [ activity_uri, object_uri ].each do |value|
      parsed = URI.parse(value.to_s)
      valid = parsed.scheme.in?(%w[http https]) && parsed.host.present? && parsed.userinfo.blank?
      errors.add(:base, :invalid) unless valid
    rescue URI::InvalidURIError, URI::InvalidComponentError
      errors.add(:base, :invalid)
    end
  end

  def payload_and_audience_are_objects
    errors.add(:payload, :invalid) unless payload.is_a?(Hash)
    errors.add(:audience, :invalid) unless audience.is_a?(Hash)
  end

  def publication_subject_integrity
    case subject_type
    when "WorkoutPublication"
      unless workout_publication_id.present? && subject_id == workout_publication_id && segment_publication_id.blank?
        errors.add(:workout_publication, :invalid)
      end
    when "SegmentPublication"
      unless segment_publication_id.present? && subject_id == segment_publication_id && workout_publication_id.blank?
        errors.add(:segment_publication, :invalid)
      end
    when "Actor"
      if workout_publication_id.present? || segment_publication_id.present?
        errors.add(:base, :invalid)
      end
    end
  end
end
