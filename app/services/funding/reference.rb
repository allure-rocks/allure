# frozen_string_literal: true

module Funding
  # Stripe accepts only alphanumerics, '-' and '_', up to 200 characters.
  # Keep the signed payload compact; its expiry is checked explicitly rather
  # than using the verifier's larger metadata envelope. Nothing is trusted
  # until the original signature has been verified.
  module Reference
    TTL = 2.hours
    MAX_LENGTH = 200

    module_function

    def generate(user:, tier:)
      raise ArgumentError, "invalid tier" unless Allure::Funding::TIERS.include?(tier)
      raise ArgumentError, "persisted account required" unless user.persisted?

      payload = [ user.id, Allure::Funding::TIERS.index(tier), (Time.current + TTL).to_i ]
      signed = verifier.generate(payload)
      message, signature = signed.split("--", 2)
      token = "#{message.tr('+/', '-_').delete('=')}_#{signature}"
      raise ArgumentError, "funding reference too long" if token.length > MAX_LENGTH

      token
    end

    # `at` is a provider-verified checkout creation time for delayed delivery.
    # A browser timestamp is never accepted here. Renewals do not call this:
    # they use the durable subscription binding instead.
    #
    # `for_billing` separates billing-lifecycle ownership from benefit
    # eligibility: a verified reference still resolves an account whose
    # deletion is scheduled, so a late initial notification can bind its
    # subscription for cancellation at purge. A purely suspended or already
    # deleted account never resolves, in either mode.
    def resolve(reference, tier:, at: Time.current, for_billing: false)
      return unless at.is_a?(Time)
      return unless reference.is_a?(String) && reference.length <= MAX_LENGTH
      return unless reference.match?(/\A[A-Za-z0-9_-]+\z/)

      message, separator, signature = reference.rpartition("_")
      return if separator.empty?

      message = message.tr("-_", "+/")
      message += "=" * ((4 - message.length % 4) % 4)
      payload = verifier.verified("#{message}--#{signature}")
      return unless payload.is_a?(Array) && payload.length == 3

      id, index, expires_at = payload
      return unless id.is_a?(Integer) && index.is_a?(Integer) && expires_at.is_a?(Integer)
      return unless index >= 0 && Allure::Funding::TIERS[index] == tier
      return unless expires_at > at.to_i && expires_at <= (at + TTL).to_i
      return if at > Time.current + 5.minutes

      user = User.find_by(id:)
      return unless user
      return user if for_billing && user.deletion_scheduled?

      user unless user.deactivated?
    end

    def verifier = Rails.application.message_verifier(:funding)
    private_class_method :verifier
  end
end
