# frozen_string_literal: true

require "uri"

class Actor < ApplicationRecord
  CAPABILITY_PROFILES = %w[unknown public_only restricted_fetch restricted_shared_inbox].freeze
  REMOTE_CACHE_TTL = 1.hour

  belongs_to :user, optional: true, inverse_of: :actor

  has_many :outgoing_followings,
           class_name: "Following",
           foreign_key: :follower_actor_id,
           inverse_of: :follower_actor
  has_many :incoming_followings,
           class_name: "Following",
           foreign_key: :followed_actor_id,
           inverse_of: :followed_actor
  has_many :inbox_items,
           class_name: "FederationInboxItem",
           foreign_key: :recipient_actor_id,
           inverse_of: :recipient_actor
  has_many :federation_outbox_events, dependent: :restrict_with_exception, inverse_of: :actor
  has_many :reactions, inverse_of: :actor, dependent: :restrict_with_exception
  has_many :comments, inverse_of: :actor, dependent: :restrict_with_exception
  has_many :workout_participations,
           foreign_key: :participant_actor_id,
           dependent: :restrict_with_exception,
           inverse_of: :participant_actor
  has_many :workout_publications, dependent: :restrict_with_exception, inverse_of: :actor
  has_many :segment_publications, dependent: :restrict_with_exception, inverse_of: :actor
  has_many :remote_notes, dependent: :restrict_with_exception, inverse_of: :actor
  has_many :remote_note_recipients,
           class_name: "RemoteNoteRecipient",
           foreign_key: :recipient_actor_id,
           dependent: :restrict_with_exception,
           inverse_of: :recipient_actor
  has_many :remote_segments, dependent: :restrict_with_exception, inverse_of: :actor
  has_many :remote_segment_recipients,
           class_name: "RemoteSegmentRecipient",
           foreign_key: :recipient_actor_id,
           dependent: :restrict_with_exception,
           inverse_of: :recipient_actor

  encrypts :private_key_ciphertext
  has_one_attached :avatar_cache, dependent: :purge_later

  scope :local, -> { where(local: true) }
  scope :remote, -> { where(local: false) }

  validates :local, inclusion: { in: [ true, false ] }
  validates :uri, presence: true, uniqueness: true
  validates :capability_profile, inclusion: { in: CAPABILITY_PROFILES }
  validates :acct, format: { with: /\A[^@\s]+@[^@\s]+\z/ }, allow_nil: true
  validate :uri_is_absolute
  validate :uri_is_immutable, if: :persisted?
  validate :local_identity_invariants
  validate :public_key_id_is_absolute
  validate :avatar_url_is_absolute

  def remote? = !local?

  def tombstoned? = tombstoned_at.present?

  # The browser only ever sees a cached copy, fetched by
  # Federation::FetchActorAvatarJob; the remote URL is never rendered.
  def avatar_cached? = remote? && avatar_cache.attached?

  def cache_fresh?(now: Time.current)
    remote? && !tombstoned? && last_fetched_at.present? && last_fetched_at > now - REMOTE_CACHE_TTL
  end

  def cache_stale?(now: Time.current) = !cache_fresh?(now:)

  def tombstone!(at: Time.current)
    with_lock do
      update!(user: nil, tombstoned_at: at)
    end
  end

  # Encrypted attributes are decrypted when serialised by Active Record. Actor
  # documents and logs must never expose the local private key.
  def serializable_hash(options = nil)
    super(options).except("private_key_ciphertext")
  end

  def inspect
    "#<#{self.class.name} id: #{id.inspect}, uri: #{uri.inspect}>"
  end

  private

  def uri_is_absolute
    parsed = URI.parse(uri.to_s)
    valid = parsed.scheme.in?(%w[http https]) && parsed.host.present? && parsed.userinfo.blank? &&
      parsed.query.blank? && parsed.fragment.blank?
    errors.add(:uri, :invalid) unless valid
  rescue URI::InvalidURIError, URI::InvalidComponentError
    errors.add(:uri, :invalid)
  end

  def uri_is_immutable
    errors.add(:uri, :immutable) if will_save_change_to_uri?
  end

  def local_identity_invariants
    if local?
      validate_local_identity
    else
      errors.add(:user, :must_be_nil) if user.present? || user_id.present?
      errors.add(:private_key_ciphertext, :must_be_nil) if private_key_ciphertext.present?
    end
  end

  def validate_local_identity
    if user.present?
      errors.add(:private_key_ciphertext, :blank) if private_key_ciphertext.blank?
      errors.add(:public_key_pem, :blank) if public_key_pem.blank?
      if uri != user.actor_uri
        errors.add(:uri, :invalid)
      end
      if !Allure::Federation.config.local_uri?(uri)
        errors.add(:uri, :invalid)
      end
    else
      errors.add(:user, :required) unless tombstoned?
      errors.add(:tombstoned_at, :present) unless tombstoned?
    end

    if private_key_ciphertext.blank? && private_key_retired_at.blank?
      errors.add(:private_key_ciphertext, :blank) if user.blank?
    end
  rescue URI::InvalidURIError, Allure::Federation::Config::InvalidBaseUrl
    errors.add(:uri, :invalid)
  end

  def public_key_id_is_absolute
    return if public_key_id.blank?

    parsed = URI.parse(public_key_id)
    errors.add(:public_key_id, :invalid) unless parsed.scheme.present? && parsed.host.present?
  rescue URI::InvalidURIError, URI::InvalidComponentError
    errors.add(:public_key_id, :invalid)
  end

  def avatar_url_is_absolute
    return if avatar_url.blank?

    parsed = URI.parse(avatar_url)
    valid = parsed.scheme.in?(%w[http https]) && parsed.host.present? &&
      parsed.userinfo.blank? && parsed.query.blank? && parsed.fragment.blank?
    errors.add(:avatar_url, :invalid) unless valid
  rescue URI::InvalidURIError, URI::InvalidComponentError
    errors.add(:avatar_url, :invalid)
  end
end
