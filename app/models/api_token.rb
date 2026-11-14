# frozen_string_literal: true

# A personal API token (PLAN_API.md §4). The secret is shown once at creation
# and only its SHA-256 digest is kept: a 256-bit random secret needs no slow
# hash, so authentication is one indexed equality.
class ApiToken < ApplicationRecord
  include HasShortId

  SCOPES = %w[read write import publish social:read webhooks].freeze
  PREFIX = "allure_pat_"
  DISPLAYED_PREFIX_LENGTH = 12
  SECRET_PATTERN = /\A#{PREFIX}[A-Za-z0-9_-]{43}\z/
  EXPIRY_DAYS = [ 30, 90, 365 ].freeze
  DEFAULT_EXPIRY_DAYS = 90
  MAX_LIVE_PER_USER = 20
  LAST_USED_RESOLUTION = 5.minutes
  RETENTION = 90.days
  REVOKERS = %w[owner operator system].freeze
  # How much location the token may hand an AI assistant through /mcp
  # (PLAN_MCP.md §4), from least to most.
  MCP_GEOMETRY_LEVELS = %w[none filtered raw].freeze

  belongs_to :user

  attribute :scopes, :string, array: true, default: -> { [] }

  validates :uuid, uniqueness: true, allow_nil: true
  validates :name, presence: true, length: { maximum: 80 }
  validates :token_prefix, :token_digest, :expires_at, presence: true
  validates :token_digest, format: { with: /\A\h{64}\z/ }
  validates :revoked_by, inclusion: { in: REVOKERS }, allow_nil: true
  validates :mcp_geometry, inclusion: { in: MCP_GEOMETRY_LEVELS }
  validate :scopes_are_known
  validate :live_tokens_are_bounded, on: :create
  validate :mcp_geometry_within_cap, on: :create

  scope :unrevoked, -> { where(revoked_at: nil) }
  scope :usable, ->(now = Time.current) { unrevoked.where("expires_at > ?", now) }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
  scope :prunable, ->(now = Time.current) {
    where("revoked_at < :cut OR expires_at < :cut", cut: now - RETENTION)
  }

  # Returns the persisted token and its secret; the secret exists only in the
  # caller's hands from here on.
  def self.issue!(user:, name:, scopes:, expires_in_days: DEFAULT_EXPIRY_DAYS, mcp_geometry: "none")
    secret = PREFIX + SecureRandom.urlsafe_base64(32)
    days = EXPIRY_DAYS.include?(expires_in_days.to_i) ? expires_in_days.to_i : DEFAULT_EXPIRY_DAYS
    token = create!(
      user:, name: name.to_s.strip, scopes: Array(scopes).map(&:to_s).uniq & SCOPES,
      token_prefix: secret.first(DISPLAYED_PREFIX_LENGTH), token_digest: digest(secret),
      expires_at: days.days.from_now, mcp_geometry: mcp_geometry.to_s
    )
    [ token, secret ]
  end

  def self.digest(secret) = OpenSSL::Digest::SHA256.hexdigest(secret.to_s)

  # The instance's ceiling on MCP location (`MCP_GEOMETRY_MAX`); unset or
  # unknown means no ceiling.
  def self.mcp_geometry_cap
    value = ENV.fetch("MCP_GEOMETRY_MAX", "").strip.downcase
    MCP_GEOMETRY_LEVELS.include?(value) ? value : MCP_GEOMETRY_LEVELS.last
  end

  # The levels an account may choose today, the ceiling included.
  def self.offered_mcp_geometry_levels
    MCP_GEOMETRY_LEVELS.first(MCP_GEOMETRY_LEVELS.index(mcp_geometry_cap) + 1)
  end

  # What the token actually gets: its own level, lowered to the ceiling.
  def effective_mcp_geometry
    cap = self.class.mcp_geometry_cap
    [ mcp_geometry, cap ].min_by { MCP_GEOMETRY_LEVELS.index(it) || 0 }
  end

  # The usable token for a presented secret, or nil. Malformed values never
  # reach the database.
  def self.authenticate(secret, now: Time.current)
    return unless secret.is_a?(String) && SECRET_PATTERN.match?(secret)

    usable(now).includes(:user).find_by(token_digest: digest(secret))
  end

  def revoked? = revoked_at.present?
  def expired?(now = Time.current) = expires_at <= now
  def usable?(now = Time.current) = !revoked? && !expired?(now)
  def scope?(scope) = scopes.include?(scope.to_s)

  def revoke!(by:)
    raise ArgumentError, "unknown revoker #{by}" unless REVOKERS.include?(by.to_s)
    return if revoked?

    update!(revoked_at: Time.current, revoked_by: by.to_s)
  end

  # Bounded write amplification: a busy client refreshes the row at most once
  # per resolution window.
  def record_use!(now = Time.current)
    return if last_used_at && last_used_at > now - LAST_USED_RESOLUTION

    update_column(:last_used_at, now)
  end

  private

  def scopes_are_known
    if scopes.blank?
      errors.add(:scopes, :blank)
    elsif (scopes - SCOPES).any?
      errors.add(:scopes, :inclusion)
    end
  end

  def live_tokens_are_bounded
    return unless user
    return if user.api_tokens.usable.count < MAX_LIVE_PER_USER

    errors.add(:base, :too_many_tokens, count: MAX_LIVE_PER_USER)
  end

  def mcp_geometry_within_cap
    return unless MCP_GEOMETRY_LEVELS.include?(mcp_geometry)
    return if self.class.offered_mcp_geometry_levels.include?(mcp_geometry)

    errors.add(:mcp_geometry, :above_instance_limit)
  end
end
