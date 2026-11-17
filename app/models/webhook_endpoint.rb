# frozen_string_literal: true

# An address an account asked Allure to notify (docs/dev/API.md). Its URL
# passes the federation SSRF guard at creation and on every change, and again
# at every attempt. The secret signs each delivery (Standard Webhooks) and is
# shown once; a rotation keeps the previous one signing for 24 hours.
class WebhookEndpoint < ApplicationRecord
  include HasShortId

  # The events an endpoint may subscribe to, grouped as the settings form
  # lists them (DESIGN.md §20.18). Only what Allure emits is offered.
  EVENT_GROUPS = {
    "workouts" => %w[workout.created workout.analyzed workout.updated workout.deleted],
    "publications" => %w[publication.activated publication.withdrawn publication.auto_failed],
    "records" => %w[record.achieved segment_effort.created],
    "social" => %w[comment.created reaction.created follow.requested follow.accepted
                   participation.requested participation.confirmed],
    "connections" => %w[import_connection.expired import_connection.revoked]
  }.freeze
  EVENT_TYPES = EVENT_GROUPS.values.flatten.freeze
  ALL_EVENTS = "*"
  MAX_PER_USER = 10
  SECRET_PREFIX = "whsec_"
  ROTATION_OVERLAP = 24.hours
  DISABLED_REASONS = %w[failing gone operator].freeze
  # Disabled after this long and this many consecutive failures (§11.4).
  FAILING_AFTER = 3.days
  FAILING_COUNT = 20

  belongs_to :user
  has_many :deliveries, class_name: "WebhookDelivery", dependent: :delete_all, inverse_of: :webhook_endpoint

  encrypts :secret, :previous_secret

  attribute :events, :string, array: true, default: -> { [] }

  validates :uuid, uniqueness: true, allow_nil: true
  validates :url, presence: true, length: { maximum: 2_048 }
  validates :description, length: { maximum: 200 }, allow_nil: true
  validates :secret, presence: true
  validates :disabled_reason, inclusion: { in: DISABLED_REASONS }, allow_nil: true
  validate :events_are_known
  validate :url_is_safe, if: :will_save_change_to_url?
  validate :endpoints_are_bounded, on: :create

  before_validation :generate_secret, on: :create
  before_validation { self.description = description.presence&.strip }

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
  scope :deliverable, -> { where(active: true, disabled_at: nil) }

  def self.new_secret = SECRET_PREFIX + Base64.strict_encode64(SecureRandom.random_bytes(32))

  def disabled? = disabled_at.present?
  def deliverable? = active? && !disabled?
  def all_events? = events == [ ALL_EVENTS ]
  def subscribed_to?(type) = all_events? || events.include?(type.to_s) || type.to_s == "ping"

  # The state badge of DESIGN.md §20.18.
  def state
    return "disabled_#{disabled_reason}" if disabled?

    active? ? "active" : "paused"
  end

  def host
    URI.parse(url).host
  rescue URI::InvalidURIError
    nil
  end

  # The secrets a delivery is signed with now: the current one, and the
  # previous one during its rotation overlap.
  def signing_secrets(now = Time.current)
    [ secret, (previous_secret if previous_secret_expires_at && previous_secret_expires_at > now) ].compact
  end

  # Returns the new secret; the old one signs alongside it for 24 hours.
  def rotate_secret!(now = Time.current)
    fresh = self.class.new_secret
    update!(previous_secret: secret, previous_secret_expires_at: now + ROTATION_OVERLAP, secret: fresh)
    fresh
  end

  # Tells the owner (the `webhook_disabled` notification, docs/dev/API.md).
  def disable!(reason, at: Time.current)
    update!(disabled_at: at, disabled_reason: reason)
    Notifications::Create.new(user:, kind: "webhook_disabled", subject: self,
                              payload: { "reason" => reason, "host" => host }).call!
  end

  # Re-enabling clears the failure count: the next failure starts a new run.
  def enable!
    update!(active: true, disabled_at: nil, disabled_reason: nil, consecutive_failures: 0, first_failure_at: nil)
    withdraw_disabled_notice
  end

  # A re-enabled endpoint's old notice goes, so a later disabling notifies
  # again.
  def withdraw_disabled_notice
    Notifications::Withdraw.new(kind: "webhook_disabled", subject: self).call!
  end

  def record_success!
    update_columns(consecutive_failures: 0, first_failure_at: nil, updated_at: Time.current) if consecutive_failures.positive?
  end

  # True when this failure disabled the endpoint.
  def record_failure!(at: Time.current)
    update_columns(consecutive_failures: consecutive_failures + 1, first_failure_at: first_failure_at || at, updated_at: at)
    return false unless consecutive_failures >= FAILING_COUNT && first_failure_at <= at - FAILING_AFTER

    disable!("failing", at:)
    true
  end

  private

  def generate_secret
    self.secret ||= self.class.new_secret
  end

  def events_are_known
    if events.blank?
      errors.add(:events, :blank)
    elsif !all_events? && (events - EVENT_TYPES).any?
      errors.add(:events, :inclusion)
    end
  end

  def url_is_safe
    Webhooks::Transport.validate_url!(url)
  rescue Webhooks::Transport::UnsafeUrl
    errors.add(:url, :unsafe)
  end

  def endpoints_are_bounded
    return unless user && user.webhook_endpoints.count >= MAX_PER_USER

    errors.add(:base, :too_many_webhooks, count: MAX_PER_USER)
  end
end
