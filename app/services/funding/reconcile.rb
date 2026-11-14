# frozen_string_literal: true

module Funding
  # Shared recovery seam for the rake task and recurring job.
  class Reconcile
    def self.call(provider:, since: nil)
      provider.reconcile(since:) do |notification|
        ProcessNotification.call(provider: provider.slug, notification:)
      end
    end
  end
end
