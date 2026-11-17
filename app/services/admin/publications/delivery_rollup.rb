# frozen_string_literal: true

module Admin
  module Publications
    # One query per page of publications: delivery tallies keyed by publication
    # id, so the oversight table shows federation state without an N+1 walk
    # through outbox events and deliveries.
    class DeliveryRollup
      def initialize(kind:, publication_ids:)
        @kind = kind
        @ids = publication_ids
      end

      def call
        return {} if @ids.empty?

        column = @kind == "courses" ? :segment_publication_id : :workout_publication_id
        table = @kind == "courses" ? "segment_publications" : "workout_publications"
        # Only the publication's own Create: an owner's comment rides on the
        # same publication with its own object (docs/dev/COMMENTS.md).
        rows = FederationDelivery.joins(:outbox_event)
          .joins("INNER JOIN #{table} ON #{table}.id = federation_outbox_events.#{column} " \
                 "AND #{table}.object_uri = federation_outbox_events.object_uri")
          .where(federation_outbox_events: { column => @ids, activity_type: "Create" })
          .group("federation_outbox_events.#{column}", :status)
          .count

        tally = Hash.new { |hash, key| hash[key] = Hash.new(0) }
        rows.each { |(publication_id, status), count| tally[publication_id][status] += count }

        @ids.index_with do |id|
          statuses = tally[id]
          {
            delivered: statuses["delivered"],
            open: statuses.values_at("pending", "retrying", "delivering", "reconciling").compact.sum,
            failed: statuses["failed"]
          }
        end
      end
    end
  end
end
