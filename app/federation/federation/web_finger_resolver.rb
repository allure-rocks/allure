# frozen_string_literal: true

require "json"
require "uri"

module Federation
  class WebFingerResolver
    class InvalidHandle < StandardError; end
    class FetchError < StandardError; end

    def initialize(client: nil, actor_resolver: nil, config: Allure::Federation.config)
      @config = config
      @client = client || Transport::Client.new(config:)
      @actor_resolver = actor_resolver || ActorResolver.new(client: @client, config:)
    end

    def resolve(handle)
      username, domain = parse_handle(handle)
      raise InvalidHandle, "local handles must not be resolved remotely" if domain == @config.domain

      response = @client.get(webfinger_uri(username, domain), headers: { "Accept" => Allure::Federation::MediaTypes::WEBFINGER })
      raise FetchError, "WebFinger request failed" unless response.status.between?(200, 299)

      document = JSON.parse(response.body)
      actor_uri = actor_uri_from(document, username:, domain:)
      validate_actor_authority!(actor_uri, domain)
      actor = @actor_resolver.resolve(actor_uri, acct: "#{username}@#{domain}")
      raise InvalidHandle, "WebFinger returned a local actor" if actor.local?

      actor
    rescue JSON::ParserError, Transport::SsrfGuard::UnsafeUri, Transport::Client::ResponseTooLarge,
           Transport::Client::NetworkError, Transport::Client::ResponseTimeout => error
      raise FetchError, error.message
    end

    private

    def parse_handle(value)
      handle = value.to_s.strip.sub(/\A@/, "").sub(/\Aacct:/i, "")
      username, domain = handle.split("@", 2)
      raise InvalidHandle, "handle must contain one remote domain" if username.blank? || domain.blank? || domain.include?("@")
      raise InvalidHandle, "handle contains invalid whitespace" if handle.match?(/\s/)

      [ username.downcase, normalize_domain(domain) ]
    end

    # A handle carries no scheme, so discovery has to pick one. It follows the
    # instance's configured protocol rather than assuming HTTPS: the Tier-2
    # federation ring speaks plain HTTP, and production cannot reach this branch
    # because the federation initializer refuses to boot on a non-HTTPS
    # FEDERATION_BASE_URL.
    def scheme = @config.protocol

    def default_port = scheme == "https" ? 443 : 80

    def normalize_domain(value)
      parsed = URI.parse("#{scheme}://#{value}")
      valid = parsed.host.present? && parsed.userinfo.blank? && parsed.path.in?([ "", "/" ]) && parsed.query.blank? && parsed.fragment.blank?
      raise InvalidHandle, "handle domain is invalid" unless valid

      if parsed.host.include?(":")
        return "[#{parsed.host}]" if parsed.port == default_port && value.end_with?("#{parsed.host}]")

        "[#{parsed.host}]:#{parsed.port}"
      else
        parsed.port == default_port ? parsed.host : "#{parsed.host}:#{parsed.port}"
      end
    rescue URI::InvalidURIError, URI::InvalidComponentError
      raise InvalidHandle, "handle domain is invalid"
    end

    def webfinger_uri(username, domain)
      parsed = URI.parse("#{scheme}://#{domain}")
      query = URI.encode_www_form("resource" => "acct:#{username}@#{domain}")
      port = if domain.start_with?("[") && domain.end_with?("]")
        nil
      elsif parsed.port == default_port && parsed.host == domain
        nil
      else
        parsed.port
      end
      URI::Generic.build(scheme:, host: parsed.host, port:, path: "/.well-known/webfinger", query:).to_s
    end

    def actor_uri_from(document, username:, domain:)
      links = document.is_a?(Hash) ? document["links"] : nil
      link = Array(links).find do |candidate|
        candidate.is_a?(Hash) && candidate["rel"] == "self" &&
          Allure::Federation::MediaTypes::ACTIVITY_PUB_ACCEPTED.include?(candidate["type"].to_s) &&
          candidate["href"].is_a?(String)
      end
      raise InvalidHandle, "WebFinger actor link is missing" unless link

      subject = document["subject"].to_s
      expected = "acct:#{username}@#{domain}"
      raise InvalidHandle, "WebFinger subject does not match handle" unless subject.blank? || subject.casecmp?(expected)

      link.fetch("href")
    end

    # A WebFinger server vouches only for actors on its own authority. Without
    # this binding a domain could alias another instance's actor under its own
    # handle, have it cached with a foreign acct, and misdirect follows
    # (docs/dev/FEDERATION.md).
    def validate_actor_authority!(actor_uri, domain)
      expected = Allure::Federation::Authority.domain("#{scheme}://#{domain}")
      actual = Allure::Federation::Authority.domain(actor_uri)
      return if expected && actual && expected.casecmp?(actual)

      raise InvalidHandle, "WebFinger actor does not belong to the queried domain"
    end
  end
end
