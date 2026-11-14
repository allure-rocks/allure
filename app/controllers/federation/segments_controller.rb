# frozen_string_literal: true

module Federation
  # The public protocol object for a course publication
  # (PLAN_SEGMENTS_FEDERATION.md §6.5). Public courses are readable by any
  # requester; followers-only courses require a verified signed request from an
  # actor the policy authorizes.
  class SegmentsController < ProtocolController
    def show
      publication = SegmentPublication.find_by_short_id!(params[:id])
      actor = publication.audience == "followers" ? verified_remote_actor : nil
      policy = Segments::PublicationPolicy.new(
        publication:,
        principal: Workouts::PublicationPrincipal.protocol(actor)
      )
      return render_not_found unless policy.allowed?(resource: :segment)

      render_protocol_json(
        Federation::Serializers::SegmentNote.new(
          publication:, actor: publication.actor
        ).call,
        status: :ok,
        content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB
      )
    rescue ArgumentError, Federation::Serializers::SegmentNote::Unavailable
      render_not_found
    end
  end
end
