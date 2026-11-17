# frozen_string_literal: true

module Federation
  module Outbox
    # The thread host's answer to a remote comment it did not accept, or no
    # longer accepts (docs/dev/COMMENTS.md): a Reject of the comment's
    # Create, addressed to its author alone, with the reason in the private
    # `_allure_reason` property. Each reason is its own activity, so a refusal
    # at receipt and a later removal never collide.
    class CommentReject
      REASONS = %w[closed not_allowed inactive full removed].freeze

      def initialize(host_actor:, author_uri:, create_activity_uri:, comment_uri:, reason:)
        raise ArgumentError, "unknown comment refusal reason" unless REASONS.include?(reason)

        @host_actor = host_actor
        @author_uri = author_uri
        @create_activity_uri = create_activity_uri
        @comment_uri = comment_uri
        @reason = reason
      end

      def call!
        EventBuilder.new(
          actor: @host_actor,
          subject_type: "Actor",
          subject_id: @host_actor.id,
          activity_type: "Reject",
          object_uri: @host_actor.uri,
          idempotency_key: "comment:reject:#{@reason}:#{@comment_uri}",
          payload: {
            "type" => "Reject",
            "actor" => @host_actor.uri,
            "object" => @create_activity_uri,
            "_allure_reason" => @reason,
            "to" => [ @author_uri ],
            "cc" => []
          },
          audience: { "to" => [ @author_uri ], "cc" => [] }
        ).call!
      end
    end
  end
end
