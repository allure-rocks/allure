# frozen_string_literal: true

module Funding
  # Called only after an adapter authenticated the event. The first verified
  # payment freezes its account, tier and period: redelivery cannot extend a
  # year, move a contribution, or undo an operator's revocation.
  class RecordContribution
    def self.call(provider:, event:)
      new(provider:, event:).call
    end

    def initialize(provider:, event:)
      @provider = provider.to_s
      @event = event
    end

    def call
      raise ActiveRecord::RecordNotFound unless Allure::Funding.enabled?
      raise ArgumentError, "invalid payment event" unless valid_event?

      contribution = FundingContribution.find_by(provider: @provider, external_id: @event.external_id)
      contribution ||= create_contribution
      if @event.kind == "refund"
        contribution.with_lock do
          contribution.update!(metadata: contribution.metadata.merge("refund_reported" => true))
        end
      end
      contribution
    end

    private

    def valid_event?
      @event.is_a?(Allure::Funding::Event) && %w[payment refund].include?(@event.kind) &&
        @provider.match?(/\A[a-z0-9_]+\z/) && @provider != "manual" &&
        Allure::Funding::TIERS.include?(@event.tier) &&
        @event.external_id.is_a?(String) && @event.external_id.present? &&
        @event.paid_at.is_a?(Time) && @event.paid_at <= Time.current &&
        @event.subscription_id.is_a?(String) && @event.subscription_id.present? &&
        @event.period_start.is_a?(Time) && @event.period_end.is_a?(Time) &&
        @event.period_end > @event.period_start
    end

    def create_contribution
      # The adapter must resolve/create this row from authenticated provider
      # facts before recording an invoice. Renewals never reuse a checkout
      # reference, which expired long before the following year's payment.
      subscription = FundingSubscription.find_by!(provider: @provider, external_id: @event.subscription_id)
      subscription.with_lock do
        user = subscription.user
        FundingContribution.transaction(requires_new: true) do
          contribution = FundingContribution.create!(
            provider: @provider, external_id: @event.external_id, user:, tier: @event.tier,
            paid_at: @event.paid_at, amount_cents: @event.amount_cents, currency: @event.currency,
            funding_subscription: subscription, starts_at: @event.period_start, expires_at: @event.period_end,
            metadata: @event.kind == "refund" ? { "refund_reported" => true } : {}
          )
          if user && @event.kind == "payment"
            ActiveRecord.after_all_transactions_commit do
              Notifications::Create.new(user:, kind: "funding_recorded", subject: contribution).call!
            end
          end
          contribution
        end
      end
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # The unique database index arbitrates concurrent webhook/recovery runs.
      # Also handle the model validation seeing the row another run committed.
      FundingContribution.find_by(provider: @provider, external_id: @event.external_id) || raise
    end
  end
end
