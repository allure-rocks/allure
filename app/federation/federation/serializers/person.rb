# frozen_string_literal: true

module Federation
  module Serializers
    class Person
      ACTIVITY_STREAMS_CONTEXT = "https://www.w3.org/ns/activitystreams"
      SECURITY_CONTEXT = "https://w3id.org/security/v1"

      def initialize(actor:)
        @actor = actor
        @config = Allure::Federation.config
      end

      def call
        user = @actor.user
        username = user&.username || @actor.handle.to_s.split("@", 2).first
        {
          "@context" => [ ACTIVITY_STREAMS_CONTEXT, SECURITY_CONTEXT ],
          "id" => @actor.uri,
          "type" => "Person",
          "preferredUsername" => username,
          "name" => @actor.display_name.presence || username,
          "summary" => safe_summary,
          "url" => @config.profile_url(username),
          "inbox" => @actor.inbox_url || "#{@actor.uri}/inbox",
          "outbox" => "#{@actor.uri}/outbox",
          "followers" => "#{@actor.uri}/followers",
          "following" => "#{@actor.uri}/following",
          "endpoints" => { "sharedInbox" => @actor.shared_inbox_url || @config.shared_inbox_uri },
          "publicKey" => {
            "id" => @actor.public_key_id,
            "owner" => @actor.uri,
            "publicKeyPem" => @actor.public_key_pem
          }
        }
      end

      private

      def safe_summary
        text = ActionView::Base.full_sanitizer.sanitize(@actor.summary.to_s)
        ERB::Util.html_escape(text)
      end
    end
  end
end
