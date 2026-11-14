# frozen_string_literal: true

module Funding
  # Attaches a still-unmatched provider subscription and all of its paid
  # invoices in one transaction. A matched row is never moved to another
  # account, and notification is emitted only after the attachment commits.
  class AttachSubscription
    def self.call(subscription:, user:, actor: nil)
      new(subscription:, user:, actor:).call
    end

    def initialize(subscription:, user:, actor:)
      @subscription = subscription
      @user = user
      @actor = actor
    end

    def call
      FundingSubscription.transaction do
        @subscription.lock!
        return false if @subscription.user_id == @user.id
        raise ActiveRecord::RecordInvalid, @subscription if @subscription.user_id.present?
        raise ActiveRecord::RecordInvalid, @subscription if @user.deactivated?

        @subscription.update!(user: @user)
        @subscription.funding_contributions.where(user_id: nil).find_each do |contribution|
          contribution.update!(user: @user)
          ActiveRecord.after_all_transactions_commit do
            Notifications::Create.new(user: @user, kind: "funding_recorded", subject: contribution).call!
          end
        end
        if @actor
          Admin::Audit.record(actor: @actor, action: :funding_attached, subject: @subscription,
                              metadata: { "user_id" => @user.id, "tier" => @subscription.tier })
        end
      end
      true
    end
  end
end
