# frozen_string_literal: true

module Funding
  # Records one verified reversal signal (refund or dispute, PAY-105) against
  # its original paid invoice. Idempotent per `(provider, external_id)`: a
  # redelivery updates only the reversal's own outcome, and the contribution
  # row is never rewritten — the badge-after-refund policy is unchanged and
  # only the operator's manual revocation removes a badge. A reversal whose
  # original payment was never recorded (foreign invoice, unmatched row) is
  # ignored: there is nothing local to review.
  class RecordReversal
    def self.call(provider:, reversal:)
      new(provider:, reversal:).call
    end

    def initialize(provider:, reversal:)
      @provider = provider.to_s
      @reversal = reversal
    end

    def call
      raise ActiveRecord::RecordNotFound unless Allure::Funding.enabled?
      raise ArgumentError, "invalid reversal" unless valid_reversal?

      contribution = FundingContribution.find_by(provider: @provider, external_id: @reversal.payment_external_id)
      return nil unless contribution

      reversal = FundingReversal.find_by(provider: @provider, external_id: @reversal.external_id)
      if reversal
        reversal.with_lock do
          reversal.update!(status: @reversal.status, amount_cents: @reversal.amount_cents,
                           currency: @reversal.currency, reported_at: @reversal.reported_at)
        end
      else
        FundingReversal.create!(
          provider: @provider, external_id: @reversal.external_id, kind: @reversal.kind,
          status: @reversal.status, amount_cents: @reversal.amount_cents, currency: @reversal.currency,
          reported_at: @reversal.reported_at, funding_contribution: contribution
        )
      end
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # The unique index arbitrates concurrent webhook/recovery runs.
      FundingReversal.find_by(provider: @provider, external_id: @reversal.external_id) || raise
    end

    private

    def valid_reversal?
      return false unless @reversal.is_a?(Allure::Funding::Reversal)
      return false unless FundingReversal::KINDS.include?(@reversal.kind)

      allowed = @reversal.kind == "refund" ? %w[succeeded failed] : %w[open won lost]
      @provider.match?(/\A[a-z0-9_]+\z/) && @provider != "manual" &&
        allowed.include?(@reversal.status) &&
        @reversal.external_id.is_a?(String) && @reversal.external_id.present? &&
        @reversal.payment_external_id.is_a?(String) && @reversal.payment_external_id.present? &&
        (@reversal.amount_cents.nil? || (@reversal.amount_cents.is_a?(Integer) && @reversal.amount_cents >= 0)) &&
        (@reversal.currency.nil? || @reversal.currency.match?(/\A[A-Z]{3}\z/)) &&
        @reversal.reported_at.is_a?(Time) && @reversal.reported_at <= Time.current
    end
  end
end
