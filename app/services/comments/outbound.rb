# frozen_string_literal: true

module Comments
  # Expansion of a comment's activities runs after the comment and its intent
  # are committed (docs/dev/COMMENTS.md). A queue error never rolls a gesture
  # back: the recovery sweep owns pending events.
  module Outbound
    def self.enqueue!(*events)
      events.flatten.compact.each do |event|
        next unless Allure::Federation::Config.enabled? && event.pending?

        ::Federation::ExpandOutboxEventJob.perform_later(event)
      rescue StandardError => error
        Rails.error.report(error, handled: true, context: { component: name, outbox_event_id: event.id })
      end
    end
  end
end
