# frozen_string_literal: true

# A provider sign-in made in the iOS companion's system browser, waiting for
# the app's web view to collect it (docs/dev/AUTH.md). The browser only knows
# the token; the app alone holds the PKCE verifier, so a token read from the
# redirect is useless on its own. A handoff is redeemed at most once, by its
# deletion, and any attempt — right or wrong — spends it.
class SessionHandoff < ApplicationRecord
  LIFETIME = 60.seconds
  CHALLENGE_FORMAT = /\A[A-Za-z0-9_-]{43}\z/
  VERIFIER_FORMAT = /\A[A-Za-z0-9\-._~]{43,128}\z/

  encrypts :payload

  validates :token_digest, presence: true, uniqueness: true
  validates :code_challenge, format: { with: CHALLENGE_FORMAT }
  validates :payload, :expires_at, presence: true

  scope :expired, ->(now = Time.current) { where(expires_at: ..now) }

  # Stores the payload and answers the token the browser carries to the app.
  def self.issue!(code_challenge:, payload:, now: Time.current)
    token = SecureRandom.urlsafe_base64(32)
    create!(token_digest: digest(token), code_challenge:, payload: payload.to_json, expires_at: now + LIFETIME)
    token
  end

  # The payload, when the token is current and the verifier answers its
  # challenge; nil otherwise.
  def self.redeem(token:, verifier:, now: Time.current)
    return if token.blank?

    handoff = transaction { lock.find_by(token_digest: digest(token))&.destroy! }
    return unless handoff && handoff.expires_at > now && handoff.answered_by?(verifier)

    JSON.parse(handoff.payload)
  end

  def self.digest(token) = OpenSSL::Digest::SHA256.hexdigest(token.to_s)

  # RFC 7636 S256: BASE64URL(SHA256(verifier)) without padding.
  def self.challenge_for(verifier)
    Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(verifier), padding: false)
  end

  def answered_by?(verifier)
    verifier.to_s.match?(VERIFIER_FORMAT) &&
      ActiveSupport::SecurityUtils.secure_compare(self.class.challenge_for(verifier), code_challenge)
  end
end
