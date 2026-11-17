# frozen_string_literal: true

module Federation
  module Serializers
    class OrderedCollection
      ACTIVITY_STREAMS_CONTEXT = "https://www.w3.org/ns/activitystreams"
      COLLECTIONS = %w[outbox followers following].freeze

      PAGE_SIZE = 20
      # A page beyond this would overflow the SQL offset; the collection is
      # public, so the bound also keeps anonymous paging bounded.
      MAX_PAGE = 100_000

      def initialize(actor:, collection:, viewer_actor: nil, page: 1)
        raise ArgumentError unless COLLECTIONS.include?(collection)

        @actor = actor
        @collection = collection
        @viewer_actor = viewer_actor
        @page = page.to_i.clamp(1, MAX_PAGE)
      end

      # Bounded pagination (docs/dev/PUBLISHING.md): totalItems and orderedItems share one
      # DB-filtered relation. Only the current page's payloads are loaded;
      # the collection never materializes every event or payload.
      def collection
        return empty_collection unless @collection == "outbox"

        {
          "@context" => ACTIVITY_STREAMS_CONTEXT,
          "id" => collection_uri,
          "type" => "OrderedCollection",
          "totalItems" => filtered_relation.count,
          "first" => "#{collection_uri}?page=1"
        }
      end

      def page
        return empty_page unless @collection == "outbox"

        offset = (@page - 1) * PAGE_SIZE
        items = filtered_relation.limit(PAGE_SIZE).offset(offset).map do |event|
          Federation::Outbox::WireAudience.for_viewer(event, @viewer_actor)
        end
        {
          "@context" => ACTIVITY_STREAMS_CONTEXT,
          "id" => "#{collection_uri}?page=#{@page}",
          "type" => "OrderedCollectionPage",
          "partOf" => collection_uri,
          "totalItems" => filtered_relation.count,
          "orderedItems" => items
        }
      end

      private

      def empty_collection
        {
          "@context" => ACTIVITY_STREAMS_CONTEXT,
          "id" => collection_uri,
          "type" => "OrderedCollection",
          "totalItems" => 0,
          "first" => "#{collection_uri}?page=1"
        }
      end

      def empty_page
        {
          "@context" => ACTIVITY_STREAMS_CONTEXT,
          "id" => "#{collection_uri}?page=#{@page}",
          "type" => "OrderedCollectionPage",
          "partOf" => collection_uri,
          "totalItems" => 0,
          "orderedItems" => []
        }
      end

      def filtered_relation
        @filtered_relation ||= begin
          relation = @actor.federation_outbox_events
            .where.not(status: "cancelled")
            .live_publication_creates
            .without_withdrawn_comments
            .order(created_at: :desc, id: :desc)
          apply_audience_filter(relation)
        end
      end

      # An accepted follow alone never grants visibility
      # (docs/dev/PUBLISHING.md). Visible means public, or directly addressed to the
      # verified viewer (immutable Delete recipients, Follow/Accept targets).
      def apply_audience_filter(relation)
        public_value = WorkoutNote::PUBLIC_AUDIENCE
        public_condition = <<~SQL.squish
          (
            COALESCE((federation_outbox_events.audience -> 'to' ? :public_value), false) OR
            COALESCE((federation_outbox_events.audience -> 'cc' ? :public_value), false) OR
            COALESCE((federation_outbox_events.audience -> 'recipients' ? :public_value), false)
          )
        SQL
        viewer_uri = @viewer_actor&.remote? && !@viewer_actor.tombstoned? ? @viewer_actor.uri : nil
        if viewer_uri.blank?
          relation.where(public_condition, public_value:)
        else
          direct_condition = <<~SQL.squish
            (
              COALESCE((federation_outbox_events.audience -> 'to' ? :viewer_uri), false) OR
              COALESCE((federation_outbox_events.audience -> 'cc' ? :viewer_uri), false) OR
              COALESCE((federation_outbox_events.audience -> 'recipients' ? :viewer_uri), false)
            )
          SQL
          relation.where("#{public_condition} OR #{direct_condition}", public_value:, viewer_uri:)
        end
      end

      def collection_uri = "#{@actor.uri}/#{@collection}"
      def page_uri = "#{collection_uri}?page=1"
    end
  end
end
