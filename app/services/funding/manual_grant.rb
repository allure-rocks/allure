# frozen_string_literal: true

module Funding
  # All manual grants commit the contribution and its audit together. Notification
  # is scheduled only after that transaction has committed.
  class ManualGrant
    def self.call(user:, actor:, tier:)
      raise ActiveRecord::RecordNotFound unless Allure::Funding.enabled?

      FundingContribution.transaction do
        contribution = user.funding_contributions.create!(provider: "manual", tier:, paid_at: Time.current)
        Admin::Audit.record(actor:, action: :funding_granted, subject: contribution,
                            metadata: { "tier" => contribution.tier, "user_id" => user.id })
        ActiveRecord.after_all_transactions_commit do
          Notifications::Create.new(user:, kind: "funding_recorded", subject: contribution).call!
        end
        contribution
      end
    end
  end
end
