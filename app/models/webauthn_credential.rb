# frozen_string_literal: true

# A passkey or security key registered as a second factor (docs/dev/AUTH.md,
# §5.2). The public key and the signature counter are what the server keeps;
# the private key never leaves the person's device.
class WebauthnCredential < ApplicationRecord
  NICKNAME_MAXIMUM = 60

  belongs_to :user

  normalizes :nickname, with: ->(value) { value.to_s.squish }

  validates :external_id, presence: true, uniqueness: true
  validates :public_key, presence: true
  validates :sign_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :nickname, presence: true, length: { maximum: NICKNAME_MAXIMUM }
end
