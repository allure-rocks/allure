# frozen_string_literal: true

require "uri"

# One comment or reply on a published workout's thread (docs/dev/COMMENTS.md). The
# thread lives on the local workout when this instance hosts it, or on a
# received note when the publication's origin hosts it. A comment is never
# edited: its author deletes it, the thread host removes it, the origin
# rejects it, and every one of those states keeps the row and its identity.
# Comments are live social state: they never enter a publication snapshot or a
# remote representation.
class Comment < ApplicationRecord
  include HasShortId

  STATUSES = %w[active deleted removed rejected].freeze
  AUDIENCES = %w[public followers].freeze
  REMOVAL_REASONS = %w[owner blocked actor_deleted closed not_allowed inactive full unknown].freeze
  MAX_BODY_LENGTH = 2_000
  # The bound on one thread, local or received (docs/dev/COMMENTS.md).
  MAX_ACTIVE_PER_THREAD = 1_000
  # The object path of a local comment (docs/dev/COMMENTS.md).
  OBJECT_PATH = "/api/v1/comment/"

  belongs_to :actor, inverse_of: :comments
  belongs_to :workout, optional: true, inverse_of: :comments
  belongs_to :remote_note, optional: true, inverse_of: :comments
  belongs_to :parent, class_name: "Comment", optional: true, inverse_of: :replies
  # The thread host whose Announce delivered a third party's comment here
  # (docs/dev/COMMENTS.md).
  belongs_to :relayed_by_actor, class_name: "Actor", optional: true
  has_many :replies, class_name: "Comment", foreign_key: :parent_id, inverse_of: :parent

  attr_readonly :actor_id, :workout_id, :remote_note_id, :uri, :in_reply_to_uri, :audience, :raw

  before_validation :assign_identity, on: :create

  validates :uuid, format: { with: Allure::ShortId::UUID_PATTERN }, uniqueness: true
  validates :uri, presence: true, uniqueness: true
  validates :in_reply_to_uri, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :audience, inclusion: { in: AUDIENCES }
  validates :removal_reason, inclusion: { in: REMOVAL_REASONS }, allow_nil: true
  validates :body, length: { maximum: MAX_BODY_LENGTH }
  validates :body, presence: true, if: :active?
  validates :published_at, presence: true
  validate :single_target
  validate :uris_are_absolute
  validate :local_identity_matches, on: :create
  validate :parent_is_a_root_on_the_same_thread
  validate :state_matches_status
  validate :json_columns_have_their_shape

  scope :active, -> { where(status: "active") }
  scope :roots, -> { where(parent_id: nil) }
  scope :chronological, -> { order(:created_at, :id) }

  def self.local_uri_for(uuid)
    Allure::Federation.config.comment_uri(Allure::ShortId.encode(uuid))
  end

  # Whether a URI names a comment of this instance, whatever its row state:
  # outbox events keep the identity after the row is gone with its workout.
  def self.local_uri?(uri)
    Allure::Federation.config.local_uri?(uri) && URI.parse(uri.to_s).path.to_s.start_with?(OBJECT_PATH)
  rescue URI::InvalidURIError, URI::InvalidComponentError
    false
  end

  def self.for_target(target)
    case target
    when Workout then where(workout: target)
    when RemoteNote then where(remote_note: target)
    else none
    end
  end

  def target = workout || remote_note

  def active? = status == "active"
  def deleted? = status == "deleted"
  def removed? = status == "removed"
  def rejected? = status == "rejected"

  def reply? = parent_id.present?

  def local_author? = actor&.local? == true

  # The actor hosting the thread: the workout's owner here, the received
  # note's author elsewhere (docs/dev/COMMENTS.md).
  def thread_host_actor = workout ? workout.user&.actor : remote_note&.actor

  # The thread host's own words, which travel to the publication's audience
  # instead of to a host (§6.2).
  def by_thread_host? = thread_host_actor.present? && actor_id == thread_host_actor.id

  # The author withdraws their own words (docs/dev/COMMENTS.md), and the
  # words go: the row keeps its identity so a late Create stays refused, never
  # the text. Written through the relation, the controlled terminal exception
  # to the readonly received object.
  def mark_deleted!(at: Time.current)
    with_lock do
      if active?
        self.class.where(id:).update_all(
          status: "deleted", deleted_at: at, updated_at: at, **self.class.scrubbed_text
        )
        reload
      end
    end
    self
  end

  # What a withdrawn comment keeps of its words: nothing.
  def self.scrubbed_text = { body: "", content_html: nil, raw: {} }

  # The thread host, a block, or the author's account deletion takes a comment
  # out of the thread (§5.3, §7.6).
  def remove!(reason:, at: Time.current)
    transition!(status: "removed", removal_reason: reason, removed_at: at)
  end

  # The origin refused a local author's comment on a received note (§7.4).
  def reject!(reason:, at: Time.current)
    transition!(status: "rejected", removal_reason: reason, rejected_at: at)
  end

  # The thread host relayed this instance's own comment back (§7.5): it took
  # it. The Announce identity lets the host's later Undo find it.
  def confirm!(activity_uri:, at: Time.current)
    with_lock do
      update!(confirmed_at: at, relay_activity_uri: activity_uri) if active? && confirmed_at.nil?
    end
    self
  end

  # The thread host stopped relaying a third party's comment: it leaves the
  # thread here with its words, which were never this instance's to keep.
  def withdraw_relay!(at: Time.current)
    with_lock do
      if active?
        self.class.where(id:).update_all(
          status: "removed", removal_reason: "unknown", removed_at: at, updated_at: at, **self.class.scrubbed_text
        )
        reload
      end
    end
    self
  end

  # The publication or note this comment's thread hangs on (§6.2 `context`):
  # a received note's own object — even under a reply still waiting for its
  # parent — else the publication the thread's root answers.
  def thread_object_uri
    return remote_note.object_uri if remote_note

    (parent || self).in_reply_to_uri
  end

  private

  # Every state change starts from `active` and is idempotent: a second
  # withdrawal of any kind leaves the first one in place.
  def transition!(**attributes)
    with_lock do
      update!(attributes) if active?
    end
    self
  end

  def assign_identity
    self.uuid ||= SecureRandom.uuid
    self.uri = self.class.local_uri_for(uuid) if uri.blank? && local_author? && uuid.to_s.match?(Allure::ShortId::UUID_PATTERN)
    self.published_at ||= Time.current
  end

  def single_target
    errors.add(:base, :invalid) unless [ workout, remote_note ].compact.one?
  end

  def uris_are_absolute
    { uri:, in_reply_to_uri:, activity_uri:, relay_activity_uri: }.each do |attribute, value|
      next if value.blank? && attribute.in?(%i[activity_uri relay_activity_uri])

      errors.add(attribute, :invalid) unless absolute_uri?(value)
    end
  end

  def absolute_uri?(value)
    parsed = URI.parse(value.to_s)
    parsed.scheme.in?(%w[http https]) && parsed.host.present? && parsed.userinfo.blank?
  rescue URI::InvalidURIError, URI::InvalidComponentError
    false
  end

  # A local author's comment is an object of this instance: its URI is minted
  # from its own identifier, never supplied.
  def local_identity_matches
    return unless local_author?
    return unless uuid.to_s.match?(Allure::ShortId::UUID_PATTERN)

    errors.add(:uri, :invalid) unless uri == self.class.local_uri_for(uuid)
  end

  # One level of replies: a reply answers a top-level comment of the same
  # thread, and a comment that already has replies never becomes a reply.
  def parent_is_a_root_on_the_same_thread
    return unless parent

    same_thread = parent.workout_id == workout_id && parent.remote_note_id == remote_note_id
    errors.add(:parent, :invalid) unless same_thread
    errors.add(:parent, :invalid) if parent.parent_id.present?
    errors.add(:parent, :invalid) if persisted? && (parent.id == id || replies.exists?)
  end

  def state_matches_status
    expected = {
      deleted_at: deleted?,
      removed_at: removed?,
      rejected_at: rejected?,
      removal_reason: removed? || rejected?
    }
    expected.each do |attribute, present|
      errors.add(attribute, :invalid) unless public_send(attribute).present? == present
    end
  end

  def json_columns_have_their_shape
    errors.add(:raw, :invalid) unless raw.is_a?(Hash)
    errors.add(:warnings, :invalid) unless warnings.is_a?(Array)
  end
end
