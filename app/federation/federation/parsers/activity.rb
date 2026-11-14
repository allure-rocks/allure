# frozen_string_literal: true

require "uri"

module Federation
  module Parsers
    class Activity
      class InvalidActivity < StandardError; end
      ActivityValue = Data.define(:id, :type, :actor, :object, :document)

      def initialize(document)
        @document = document
      end

      def call
        raise InvalidActivity, "activity must be an object" unless @document.is_a?(Hash)

        id = required_string("id")
        type = required_string("type")
        actor = required_string("actor")
        validate_uri!(id, "activity id")
        validate_uri!(actor, "activity actor")
        validate_id_authority!(id, actor)
        object = @document["object"]
        validate_object!(type, object)

        ActivityValue.new(id, type, actor, object, @document.deep_stringify_keys)
      end

      private

      def required_string(key)
        value = @document[key]
        raise InvalidActivity, "activity #{key} is missing" unless value.is_a?(String) && value.present?

        value
      end

      def validate_uri!(value, label)
        parsed = URI.parse(value)
        valid = parsed.scheme.in?(%w[http https]) && parsed.host.present? && parsed.userinfo.blank? && parsed.fragment.blank?
        raise InvalidActivity, "activity #{label} is invalid" unless valid
      rescue URI::InvalidURIError, URI::InvalidComponentError
        raise InvalidActivity, "activity #{label} is invalid"
      end

      # An activity is minted by its actor's server, so its id lives on the
      # actor's authority — the binding the Create parser and the Delete
      # handler already apply to their objects. Without it the id is free
      # text, and Allure's own activity URIs are deterministic
      # (Federation::Outbox::EventBuilder): a third party could admit any
      # activity under the URI a peer's future Delete or Follow will carry,
      # and the genuine activity would then be refused as a duplicate with
      # different content — a withdrawal that never lands, a follow that can
      # never be sent.
      def validate_id_authority!(id, actor)
        actor_authority = Allure::Federation::Authority.domain(actor)
        return if actor_authority && actor_authority == Allure::Federation::Authority.domain(id)

        raise InvalidActivity, "activity id authority does not match the actor"
      end

      def validate_object!(type, object)
        return if object.blank? && type.in?(%w[Create Update Delete])
        raise InvalidActivity, "activity object is missing" if object.blank?

        case type
        when "Follow", "Like"
          validate_uri!(object, "activity object") if object.is_a?(String)
          raise InvalidActivity, "activity object is invalid" unless object.is_a?(String)
        when "Accept"
          if object.is_a?(String)
            validate_uri!(object, "activity object")
          elsif object.is_a?(Hash)
            validate_uri!(object["id"], "activity object id")
          else
            raise InvalidActivity, "activity object is invalid"
          end
        when "Undo"
          validate_undo_object!(object)
        end
      end

      def validate_undo_object!(object)
        if object.is_a?(String)
          validate_uri!(object, "activity object")
        elsif object.is_a?(Hash)
          validate_uri!(object["id"], "activity object id")
          raise InvalidActivity, "undo object type is missing" unless object["type"].is_a?(String)
        else
          raise InvalidActivity, "activity object is invalid"
        end
      end
    end
  end
end
