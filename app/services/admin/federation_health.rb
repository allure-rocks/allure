# frozen_string_literal: true

module Admin
  # Delivery and relationship health for the federation panel: open delivery
  # counts, the age of the oldest unattempted delivery, the authorities with
  # the most failures, and pending follow requests. Aggregates only, per the
  # operator diagnostics privacy contract (PLAN_M5 §12.5).
  class FederationHealth
    FAILING_PREVIEW = 10

    Result = Data.define(:delivery_counts, :oldest_open_at, :failing_authorities, :pending_follow_requests)

    def call
      open = FederationDelivery.where(status: %w[pending retrying delivering reconciling])

      Result.new(
        delivery_counts: FederationDelivery.group(:status).count,
        oldest_open_at: open.minimum(:created_at),
        failing_authorities: failing_authorities,
        pending_follow_requests: Following.where(status: "pending").count
      )
    end

    private

    def failing_authorities
      totals = Hash.new(0)
      FederationDelivery.where(status: "failed").group(:inbox_url).count.each do |inbox_url, count|
        totals[Allure::Federation::Authority.domain(inbox_url) || "?"] += count
      end
      totals.sort_by { |_, count| -count }.first(FAILING_PREVIEW).to_h
    end
  end
end
