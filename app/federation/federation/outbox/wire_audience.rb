# frozen_string_literal: true

module Federation
  module Outbox
    # The addressing a payload carries on the wire for one destination
    # (docs/dev/FEDERATION.md, §12.6). An event that names its recipients one by one —
    # an actor Delete, the Delete of a withdrawn publication or comment —
    # keeps the whole list on the outbox row for expansion, but each
    # destination only sees the actors of its own authorities: the list is the
    # account's remote followers and contacts, which the collections keep
    # hidden. `#Public` and the followers collection pass unchanged.
    #
    # The projection depends only on the destination's authorities, so every
    # delivery to one peer carries the same body, which its duplicate check
    # requires.
    module WireAudience
      ADDRESSING_KEYS = %w[to cc bto bcc recipients].freeze

      module_function

      def project(payload:, audience:, authorities:)
        listed = Array(audience.to_h["recipients"]).select { |value| value.is_a?(String) }.to_set
        return payload if listed.empty?

        allowed = authorities.compact.to_set
        payload.each_with_object({}) do |(key, value), projected|
          projected[key] = if ADDRESSING_KEYS.include?(key) && value.is_a?(Array)
            value.select { |uri| !listed.include?(uri) || allowed.include?(Allure::Federation::Authority.domain(uri)) }
          else
            value
          end
        end
      end

      def for_delivery(delivery)
        event = delivery.outbox_event
        authorities = delivery.recipients.pluck(:actor_uri).map { Allure::Federation::Authority.domain(_1) }
        project(payload: event.payload, audience: event.audience, authorities:)
      end

      def for_viewer(event, viewer_actor)
        authority = viewer_actor && Allure::Federation::Authority.domain(viewer_actor.uri)
        project(payload: event.payload, audience: event.audience, authorities: [ authority ])
      end
    end
  end
end
