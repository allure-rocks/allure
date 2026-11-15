# frozen_string_literal: true

require "json"
require "openssl"
require "uri"

module Federation
  class ActorResolver
    class InvalidActor < StandardError; end
    class FetchError < StandardError; end
    # The peer could not answer now (network, timeout, 5xx, 429): worth
    # another try, and no reason to distrust a cached copy.
    class Unavailable < FetchError; end
    # The peer says the actor is gone (410).
    class Gone < FetchError; end

    UNAVAILABLE_STATUSES = [ 408, 425, 429 ].freeze

    # An actor document is a few kilobytes on every known implementation. The
    # cap bounds both the transfer and the `raw` column a hostile document
    # would otherwise fill up to the transport's 1 MB limit (docs/dev/FEDERATION.md).
    MAX_DOCUMENT_BYTES = 256.kilobytes

    # A signer is resolved inside the request thread of an unauthenticated
    # inbox POST or signed GET: its fetch gets a tighter budget than the
    # background jobs, so an attacker-chosen actor URI costs little.
    INBOUND_TOTAL_TIMEOUT = 8
    INBOUND_MAX_REDIRECTS = 1

    def self.inbound(**)
      new(total_timeout: INBOUND_TOTAL_TIMEOUT, max_redirects: INBOUND_MAX_REDIRECTS, **)
    end

    def initialize(client: nil, config: Allure::Federation.config, now: Time.current,
                   total_timeout: Transport::Client::TOTAL_TIMEOUT, max_redirects: Transport::Client::MAX_REDIRECTS)
      @client = client || Transport::Client.new(config:)
      @now = now
      @total_timeout = total_timeout
      @max_redirects = max_redirects
    end

    # With `persist: false` a fetched or refreshed actor is validated but
    # returned unsaved, so the caller can save it only once the request it
    # was fetched for has proven that it holds the matching private key.
    #
    # With `stale_ok: true` a cached remote actor whose refresh cannot reach
    # its instance right now is returned as it is: fan-out must not drop a
    # follower because its instance is restarting.
    def resolve(uri, refresh: false, acct: nil, persist: true, stale_ok: false)
      actor_uri = validate_actor_uri(uri)
      raise InvalidActor, "actor is blocked" if Safety::Blocks.blocked?(actor_uri)

      cached = Actor.find_by(uri: actor_uri)
      return cached if cached&.local?
      return cached if cached&.remote? && !refresh && cached.cache_fresh?(now: @now)

      fetch(actor_uri, acct:, persist:)
    rescue Unavailable
      raise unless stale_ok && cached&.remote? && !cached.tombstoned?

      cached
    end

    def invalidate!(uri)
      actor = Actor.remote.find_by(uri: uri.to_s)
      actor&.update!(last_fetched_at: nil)
      actor
    end

    private

    def fetch(actor_uri, acct:, persist:)
      response = @client.get(
        actor_uri,
        headers: { "Accept" => Allure::Federation::MediaTypes::ACTIVITY_PUB },
        max_bytes: MAX_DOCUMENT_BYTES,
        total_timeout: @total_timeout,
        max_redirects: @max_redirects
      )
      status = response.status.to_i
      raise Gone, "remote actor is gone" if status == 410
      if status >= 500 || UNAVAILABLE_STATUSES.include?(status)
        raise Unavailable, "remote actor fetch answered HTTP #{status}"
      end
      raise FetchError, "remote actor fetch answered HTTP #{status}" unless status.between?(200, 299)

      document = JSON.parse(response.body)
      attributes = validate_document(document, actor_uri)
      existing = Actor.find_by(uri: actor_uri)
      return existing if existing&.local?

      actor = existing || Actor.new(local: false, uri: actor_uri, capability_profile: "unknown")
      refreshed = attributes.merge(last_fetched_at: @now, raw: document)
      refreshed[:acct] = acct if acct.present?
      actor.assign_attributes(refreshed)
      # Capability is local policy, never the remote document. A policy
      # assignment overrides; without one the stored value is preserved so a
      # metadata refresh cannot silently demote a peer.
      policy_capability = PeerPolicy.capability_for(actor_uri)
      actor.capability_profile = policy_capability if policy_capability.present?
      persist ? actor.save! : actor.validate!
      actor
    rescue JSON::ParserError, ActiveRecord::RecordInvalid => error
      raise InvalidActor, error.message
    rescue Transport::Client::NetworkError, Transport::Client::ResponseTimeout => error
      raise Unavailable, error.message
    rescue Transport::SsrfGuard::UnsafeUri, Transport::Client::ResponseTooLarge,
           Transport::Client::TooManyRedirects, Transport::Client::UnsafeRedirect => error
      raise FetchError, error.message
    end

    def validate_actor_uri(uri)
      value = uri.to_s
      parsed = URI.parse(value)
      valid = parsed.absolute? && parsed.host.present? && parsed.userinfo.blank? &&
        parsed.query.blank? && parsed.fragment.blank?
      raise InvalidActor, "actor URI is invalid" unless valid

      @client.validate_url(value)
      value
    rescue URI::InvalidURIError, URI::InvalidComponentError, Transport::SsrfGuard::UnsafeUri
      raise InvalidActor, "actor URI is invalid"
    end

    def validate_document(document, actor_uri)
      raise InvalidActor, "actor document must be an object" unless document.is_a?(Hash)
      raise InvalidActor, "actor document has a mismatched id" unless document["id"] == actor_uri
      raise InvalidActor, "actor document is not a Person" unless document["type"] == "Person"

      public_key = document["publicKey"]
      raise InvalidActor, "actor document has no public key" unless public_key.is_a?(Hash)
      raise InvalidActor, "public key owner is invalid" unless public_key["owner"] == actor_uri
      key_id = validate_key_id(public_key.fetch("id"))
      key = OpenSSL::PKey.read(public_key.fetch("publicKeyPem"))
      raise InvalidActor, "public key must not be private" if key.private?

      inbox = validate_endpoint(document["inbox"], required: true)
      shared_inbox = validate_endpoint(document.dig("endpoints", "sharedInbox"), required: false)
      {
        handle: handle_for(document, actor_uri),
        display_name: document["name"].to_s.presence,
        summary: summary_for(document),
        avatar_url: avatar_url_for(document),
        public_key_id: key_id,
        public_key_pem: public_key.fetch("publicKeyPem"),
        inbox_url: inbox,
        shared_inbox_url: shared_inbox
      }
    rescue KeyError, OpenSSL::PKey::PKeyError, ArgumentError => error
      raise InvalidActor, error.message
    end

    # ActivityPub `icon` may be a URL string, an object, or an array. Only a
    # single absolute http(s) image URL is cached; anything else is ignored.
    def avatar_url_for(document)
      icon = document["icon"]
      value = case icon
      when String then icon
      when Hash then icon["url"]
      when Array then icon.filter_map { |entry| entry.is_a?(Hash) ? entry["url"] : entry }.first
      end
      return if value.blank? || !value.is_a?(String)

      parsed = URI.parse(value)
      return unless parsed.scheme.in?(%w[http https]) && parsed.host.present? &&
        parsed.userinfo.blank? && parsed.query.blank? && parsed.fragment.blank?

      value
    rescue URI::InvalidURIError, URI::InvalidComponentError
      nil
    end

    def validate_endpoint(value, required:)
      return if value.blank? && !required
      raise InvalidActor, "actor endpoint is missing" if value.blank?

      @client.validate_url(value)
      value
    rescue Transport::SsrfGuard::UnsafeUri
      raise InvalidActor, "actor endpoint is unsafe"
    end

    def validate_key_id(value)
      parsed = URI.parse(value.to_s)
      valid = parsed.absolute? && parsed.scheme.in?(%w[http https]) && parsed.host.present? &&
        parsed.userinfo.blank? && parsed.query.blank?
      raise InvalidActor, "public key id is invalid" unless valid

      value
    rescue URI::InvalidURIError, URI::InvalidComponentError
      raise InvalidActor, "public key id is invalid"
    end

    # Actor summaries are display-only; the cap keeps a hostile document from
    # storing an unbounded blob (docs/dev/FEDERATION.md).
    def summary_for(document)
      value = document["summary"].to_s
      value[0, 2_000].presence
    end

    def handle_for(document, actor_uri)
      username = document["preferredUsername"].to_s
      return if username.blank?

      authority = Allure::Federation::Authority.domain(actor_uri)
      return if authority.blank?

      "#{username}@#{authority}"
    end
  end
end
