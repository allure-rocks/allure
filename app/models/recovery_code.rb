# frozen_string_literal: true

# One-time recovery codes (PLAN_AUTH.md §4.3). Ten per generation, each shown
# once and usable once. A code carries 50 random bits, so a keyed HMAC is
# enough to keep the stored digest useless without the application secret,
# and it lets a code be found by its digest instead of trying every row.
class RecoveryCode < ApplicationRecord
  COUNT = 10
  # Lowercase base32 without the characters people misread (0/o, 1/l/i).
  ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789".chars.freeze
  HALF_LENGTH = 5

  belongs_to :user

  validates :code_digest, presence: true, uniqueness: true

  scope :unused, -> { where(used_at: nil) }

  class << self
    # Replaces the account's codes and returns the new ones in clear text,
    # the only time they exist outside the person's hands.
    def generate_for!(user)
      codes = Array.new(COUNT) { random_code }
      transaction do
        user.recovery_codes.delete_all
        now = Time.current
        insert_all!(codes.map { |code| { user_id: user.id, code_digest: digest(code), created_at: now } })
      end
      codes
    end

    # Marks the matching unused code as used. Two concurrent submissions of
    # the same code cannot both succeed.
    def consume(user, input, now: Time.current)
      normalized = normalize(input)
      return false unless normalized

      user.recovery_codes.unused.where(code_digest: digest(normalized)).update_all(used_at: now) == 1
    end

    def normalize(input)
      compact = input.to_s.downcase.gsub(/[\s-]/, "")
      return unless compact.length == HALF_LENGTH * 2 && compact.chars.all? { |char| ALPHABET.include?(char) }

      "#{compact[0, HALF_LENGTH]}-#{compact[HALF_LENGTH, HALF_LENGTH]}"
    end

    def digest(code)
      OpenSSL::HMAC.hexdigest("SHA256", key, code)
    end

    private

    def random_code
      "#{Array.new(HALF_LENGTH) { ALPHABET.sample(random: SecureRandom) }.join}-" \
        "#{Array.new(HALF_LENGTH) { ALPHABET.sample(random: SecureRandom) }.join}"
    end

    def key = Rails.application.key_generator.generate_key("allure/recovery-codes", 32)
  end
end
