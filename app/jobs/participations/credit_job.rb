# frozen_string_literal: true

module Participations
  # Creates or re-attaches the credit row of a confirmed credit
  # (PLAN_TOGETHER.md §5). A link, or a participation withdrawn before the job
  # ran, is a no-op.
  class CreditJob < ApplicationJob
    queue_as :default

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::RecordNotUnique, wait: :polynomially_longer, attempts: 5
    discard_on ActiveJob::DeserializationError

    # A participant who already holds their own recording of the outing is
    # offered the link at once (PLAN_TOGETHER.md §8).
    def perform(participation)
      CreditRows.attach(participation)
      Together::CreditLinkSuggestion.for_participation(participation.reload)
    end
  end
end
