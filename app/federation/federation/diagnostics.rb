# frozen_string_literal: true

module Federation
  # Operator-facing aggregates for the federation settings page (PLAN_M5
  # §12.5). Counts and identifiers only: it never returns coordinates, raw
  # payloads, inbox bodies, keys, or remote HTML.
  class Diagnostics
    UNKNOWN = "?"

    Result = Data.define(
      :inbox_items, :deliveries, :media, :remote_notes, :remote_segments,
      :domain_blocks, :actor_blocks, :peer_policies, :retryable_media
    )

    def call
      Result.new(
        inbox_items: status_counts(FederationInboxItem),
        deliveries: delivery_counts,
        media: combined_media_counts,
        remote_notes: status_counts(RemoteNote),
        remote_segments: status_counts(RemoteSegment),
        domain_blocks: FederationDomainBlock.order(:domain).to_a,
        actor_blocks: FederationActorBlock.order(:actor_uri).to_a,
        peer_policies: FederationPeerPolicy.order(:domain).to_a,
        retryable_media: retryable_media_count
      )
    end

    private

    def status_counts(model)
      model.group(:status).count
    end

    # Note and course descriptors share one operator-facing summary.
    def combined_media_counts
      status_counts(RemoteNoteAttachment)
        .merge(status_counts(RemoteSegmentAttachment)) { |_status, notes, segments| notes + segments }
    end

    def retryable_media_count
      [ RemoteNoteAttachment, RemoteSegmentAttachment ].sum do |model|
        model.where(status: %w[failed unavailable]).count
      end
    end

    # Deliveries carry an inbox URL, never a stored authority, so the target
    # domain is derived here and only the tuple is returned.
    def delivery_counts
      counts = Hash.new(0)
      FederationDelivery.pluck(:status, :inbox_url).each do |status, inbox_url|
        counts[[ status, Allure::Federation::Authority.domain(inbox_url) || UNKNOWN ]] += 1
      end
      counts.sort_by { |(status, domain), _count| [ status.to_s, domain.to_s ] }
    end
  end
end
