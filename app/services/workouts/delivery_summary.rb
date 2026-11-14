# frozen_string_literal: true

require "uri"

module Workouts
  # Plain-language delivery state for an active publication, derived from its
  # Create intent and deliveries. Never mentions queue, signature, HTTP,
  # capability, or retry internals, and never implies delivery controls who
  # can fetch the public publication.
  class DeliverySummary
    Result = Data.define(
      :state, :delivered_accounts, :delivered_servers, :failed_deliveries
    )

    def initialize(publication:)
      @publication = publication
    end

    def call
      return Result.new(state: :federation_disabled, delivered_accounts: 0, delivered_servers: 0, failed_deliveries: 0) unless Allure::Federation::Config.enabled?

      # The publication's own Create: an owner's comment rides on the same
      # publication with its own object (PLAN_COMMENTS.md §9) and never
      # changes the publication's state.
      create_event = PublicationWithdrawal.find_create_event(@publication)
      return Result.new(state: :no_recipients, delivered_accounts: 0, delivered_servers: 0, failed_deliveries: 0) unless create_event

      deliveries = create_event.deliveries.to_a
      return Result.new(state: :pending, delivered_accounts: 0, delivered_servers: 0, failed_deliveries: 0) if !create_event.terminal? && (deliveries.empty? || deliveries.any? { !_1.terminal? })
      return Result.new(state: :no_recipients, delivered_accounts: 0, delivered_servers: 0, failed_deliveries: 0) if deliveries.empty?

      delivered_uris = deliveries.select(&:delivered?).flat_map { |delivery| delivery.recipients.pluck(:actor_uri) }.uniq
      failed = deliveries.count(&:failed?)

      if delivered_uris.any? && failed.zero?
        Result.new(state: :delivered, delivered_accounts: delivered_uris.length, delivered_servers: server_count(delivered_uris), failed_deliveries: 0)
      elsif delivered_uris.any?
        Result.new(state: :partial, delivered_accounts: delivered_uris.length, delivered_servers: server_count(delivered_uris), failed_deliveries: failed)
      elsif failed.positive?
        Result.new(state: :unavailable, delivered_accounts: 0, delivered_servers: 0, failed_deliveries: failed)
      else
        Result.new(state: :no_recipients, delivered_accounts: 0, delivered_servers: 0, failed_deliveries: 0)
      end
    end

    private

    def server_count(actor_uris)
      actor_uris.filter_map do |uri|
        URI.parse(uri.to_s).host
      rescue URI::InvalidURIError, URI::InvalidComponentError
        nil
      end.uniq.length
    end
  end
end
