# frozen_string_literal: true

require "uri"

module Federation
  module Signature
    class RequestActor
      class InvalidRequest < StandardError; end

      def initialize(method:, path:, headers:, body: "", actor_resolver: nil, verifier: nil)
        @method = method
        @path = path
        @headers = headers
        @body = body
        @actor_resolver = actor_resolver || ActorResolver.inbound
        @verifier = verifier || Signature::Verifier.new
      end

      def call!
        prepared = @verifier.prepare(method: @method, path: @path, headers: @headers, body: @body)
        actor_uri = actor_uri_from_key_id(prepared.signature.fetch("keyid"))
        actor = SignerResolution.new(actor_resolver: @actor_resolver, verifier: @verifier)
          .call(actor_uri:, prepared:, persist: false, known_only: true).actor
        unless actor.public_key_id == prepared.signature.fetch("keyid")
          raise InvalidRequest, "signature key does not belong to a usable remote actor"
        end

        # A refreshed actor is saved only once its key has verified this
        # request, as Inbox::Admission does.
        actor.save! if actor.changed?
        actor
      rescue Signature::Verifier::InvalidSignature, ActorResolver::InvalidActor, ActorResolver::FetchError,
             Safety::ResolutionAttempts::Exceeded, ActiveRecord::RecordInvalid, URI::InvalidURIError, URI::InvalidComponentError, KeyError => error
        raise InvalidRequest, error.message
      end

      private

      def actor_uri_from_key_id(key_id)
        uri = URI.parse(key_id.to_s)
        valid = uri.scheme.in?(%w[http https]) && uri.host.present? && uri.userinfo.blank? &&
          uri.query.blank? && uri.fragment.present?
        raise InvalidRequest, "signature key ID is invalid" unless valid

        uri.fragment = nil
        uri.to_s
      end
    end
  end
end
