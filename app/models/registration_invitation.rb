# frozen_string_literal: true

# Operator-issued, single-use registration invitations. Only the SHA-256 digest
# of the token is stored, so a database leak cannot reveal live links; the raw
# token exists only in the generated URL. The address is bound at issue time:
# the invitation form prefills it, the server imposes it, and accepting the
# invitation is recorded on the row. An optional display name only prefills
# the new account's name, which the invitee may change.
class RegistrationInvitation < ApplicationRecord
  TOKEN_BYTES = 32
  DEFAULT_EXPIRY = 7.days

  normalizes :email_address, with: ->(email) { email.to_s.strip.downcase }
  normalizes :display_name, with: ->(name) { name.to_s.squish.presence }

  validates :token_digest, presence: true, uniqueness: true
  validates :email_address, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :display_name, length: { maximum: 60 }, allow_blank: true
  validates :expires_at, presence: true

  scope :pending, -> { where(accepted_at: nil).where(expires_at: Time.current..) }

  # Creates an invitation and returns [invitation, raw_token]. The raw token is
  # returned to the caller and never persisted.
  def self.issue(email_address:, display_name: nil, expires_in: DEFAULT_EXPIRY)
    raw_token = SecureRandom.urlsafe_base64(TOKEN_BYTES)
    invitation = create!(
      email_address:,
      display_name:,
      expires_at: expires_in.from_now,
      token_digest: digest(raw_token)
    )

    [ invitation, raw_token ]
  end

  # The presented token is hashed before lookup, so database reads never compare
  # a stored plaintext secret.
  def self.find_by_token(raw_token)
    return nil if raw_token.blank?

    find_by(token_digest: digest(raw_token))
  end

  def self.digest(raw_token) = Digest::SHA256.hexdigest(raw_token.to_s)

  def usable? = accepted_at.nil? && expires_at.future?
  def accepted? = accepted_at.present?
  def expired? = expires_at.past?

  def accept! = update!(accepted_at: Time.current)
end
