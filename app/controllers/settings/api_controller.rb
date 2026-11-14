# frozen_string_literal: true

module Settings
  # « API et webhooks » (DESIGN.md §20.18, PLAN_API.md §4.4): the account's
  # API tokens. Webhooks join this page with their slice.
  class ApiController < ApplicationController
    def show
      @tokens = current_user.api_tokens.where("revoked_at IS NULL OR revoked_at > ?", ApiToken::RETENTION.ago)
                            .newest_first
      @webhooks = current_user.webhook_endpoints.newest_first.to_a
      @last_deliveries = WebhookDelivery.where(webhook_endpoint: @webhooks)
                                        .select("DISTINCT ON (webhook_endpoint_id) webhook_deliveries.*")
                                        .order(:webhook_endpoint_id, created_at: :desc, id: :desc)
                                        .index_by(&:webhook_endpoint_id)
    end
  end
end
