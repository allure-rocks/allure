# frozen_string_literal: true

# The push subscription of one signed-in session on the iOS companion
# (docs/dev/PUSH.md). The endpoint is a relay URL listed in
# `PUSH_RELAY_ORIGINS` — the instance never posts a push anywhere else — and
# `p256dh`/`auth` are the device's RFC 8291 keys the payload is encrypted for.
# The row goes with its session through the foreign-key cascade.
class PushSubscription < ApplicationRecord
  P256DH_BYTES = 65
  AUTH_BYTES = 16
  MAX_ENDPOINT_LENGTH = 2_048
  # Consecutive failed deliveries after which the subscription is dropped.
  MAX_FAILURES = 10

  belongs_to :user
  belongs_to :session

  encrypts :endpoint, :auth

  validates :endpoint, presence: true, length: { maximum: MAX_ENDPOINT_LENGTH }
  validates :endpoint_digest, presence: true, uniqueness: true
  validates :session_id, uniqueness: true
  validates :failure_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :endpoint_is_a_listed_relay
  validate :keys_are_well_formed
  validate :session_belongs_to_user

  before_validation :normalize

  def self.digest(endpoint) = Digest::SHA256.hexdigest(endpoint.to_s)

  def self.find_by_endpoint(endpoint)
    return if endpoint.blank?

    find_by(endpoint_digest: digest(endpoint))
  end

  def record_success!(at: Time.current)
    update_columns(last_success_at: at, failure_count: 0, updated_at: at)
  end

  # Returns true when the subscription was dropped after too many failures.
  def record_failure!(at: Time.current)
    count = failure_count + 1
    if count >= MAX_FAILURES
      destroy!
      true
    else
      update_columns(failure_count: count, updated_at: at)
      false
    end
  end

  private

  def normalize
    self.endpoint = endpoint.to_s.strip.presence
    self.endpoint_digest = self.class.digest(endpoint) if endpoint
    self.p256dh = canonical_key(p256dh)
    self.auth = canonical_key(auth)
  end

  # Unpadded base64url, whatever padding or alphabet the device sent.
  def canonical_key(value)
    bytes = Allure::Push::Config.decode(value)
    bytes ? Allure::Push::Config.encode(bytes) : value.to_s.strip.presence
  end

  def endpoint_is_a_listed_relay
    return if endpoint.blank?

    uri = URI.parse(endpoint)
    valid = uri.is_a?(URI::HTTP) && uri.query.nil? && uri.fragment.nil? &&
      Allure::Push::Config.relay_origin?(endpoint)
    errors.add(:endpoint, :invalid) unless valid
  rescue URI::InvalidURIError, URI::InvalidComponentError
    errors.add(:endpoint, :invalid)
  end

  def keys_are_well_formed
    key = Allure::Push::Config.decode(p256dh)
    errors.add(:p256dh, :invalid) unless key && key.bytesize == P256DH_BYTES && key.getbyte(0) == 4 && on_curve?(key)
    secret = Allure::Push::Config.decode(auth)
    errors.add(:auth, :invalid) unless secret && secret.bytesize == AUTH_BYTES
  end

  def on_curve?(key)
    group = OpenSSL::PKey::EC::Group.new("prime256v1")
    OpenSSL::PKey::EC::Point.new(group, OpenSSL::BN.new(key, 2)).on_curve?
  rescue OpenSSL::PKey::EC::Point::Error, OpenSSL::PKey::ECError
    false
  end

  def session_belongs_to_user
    errors.add(:session, :invalid) if session && user_id && session.user_id != user_id
  end
end
