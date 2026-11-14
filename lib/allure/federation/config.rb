# frozen_string_literal: true

require "uri"

module Allure
  module Federation
    # The instance's federated identity.
    #
    # Everything that ends up in a signed object — actor URIs, object IDs,
    # WebFinger subjects, the key id — derives from here. Nothing anywhere else
    # is allowed to hardcode a host.
    #
    # This matters more than it looks. An actor URI is permanent: remote servers
    # store it, and changing the host later does not migrate anything. It breaks
    # every existing follow while remote instances keep POSTing to an endpoint
    # that no longer answers. The port is part of that identity too, which is why
    # it is carried explicitly rather than being normalised away.
    #
    # See PLAN.md §6 for the testing tiers this is designed to support.
    class Config
      class InvalidBaseUrl < StandardError; end

      DEFAULT_BASE_URL = "http://allure.test:3001"
      SUPPORTED_PROTOCOLS = %w[http https].freeze

      attr_reader :base_url, :host, :port, :scheme, :protocol

      def self.enabled?
        default = defined?(Rails) && Rails.env.production? ? "false" : "true"
        ActiveModel::Type::Boolean.new.cast(ENV.fetch("FEDERATION_ENABLED", default)) == true
      end

      # The separately gated restricted audience (PLAN_M5 §13.1). It defaults
      # to false in every environment; enabling it makes the built-in followers
      # profile publishable without changing any public behavior.
      def self.restricted_enabled?
        ActiveModel::Type::Boolean.new.cast(ENV.fetch("FEDERATION_RESTRICTED_ENABLED", "false")) == true
      end

      def initialize(base_url: nil, protocol: nil, allow_private_ips: nil)
        raw_base_url = base_url || ENV["FEDERATION_BASE_URL"] || DEFAULT_BASE_URL
        uri = parse_base_url(raw_base_url)
        configured_protocol = protocol || (base_url.nil? ? ENV["FEDERATION_PROTOCOL"] : nil) || uri.scheme

        @protocol = normalize_protocol(configured_protocol)
        unless uri.scheme == @protocol
          raise InvalidBaseUrl, "FEDERATION_PROTOCOL must match FEDERATION_BASE_URL scheme"
        end

        @base_url = uri.to_s.chomp("/")
        @scheme = uri.scheme
        @host = uri.host
        @port = uri.port

        @allow_private_ips =
          if allow_private_ips.nil?
            ActiveModel::Type::Boolean.new.cast(ENV.fetch("ALLOW_PRIVATE_IPS", "false")) || false
          else
            allow_private_ips
          end
      end

      # The WebFinger domain, i.e. the right-hand side of @user@domain.
      # Includes the port when non-default, because that is what remote servers
      # will use to address us.
      def domain
        default_port = (scheme == "https" ? 443 : 80)
        port == default_port ? host : "#{host}:#{port}"
      end

      def actor_uri(username) = "#{base_url}/users/#{username}"
      def key_id(username) = "#{actor_uri(username)}#main-key"
      def inbox_uri(username) = "#{actor_uri(username)}/inbox"
      def outbox_uri(username) = "#{actor_uri(username)}/outbox"
      def followers_uri(username) = "#{actor_uri(username)}/followers"
      def following_uri(username) = "#{actor_uri(username)}/following"
      def profile_url(username) = "#{base_url}/@#{username}"
      def shared_inbox_uri = "#{base_url}/inbox"
      def webfinger_uri = "#{base_url}/.well-known/webfinger"
      def nodeinfo_uri(version) = "#{base_url}/nodeinfo/#{version}"
      def workout_publication_uri(short_id) = "#{base_url}/api/v1/trail/#{short_id}"
      def segment_publication_uri(short_id) = "#{base_url}/api/v1/segment/#{short_id}"
      def comment_uri(short_id) = "#{base_url}/api/v1/comment/#{short_id}"

      def handle(username) = "#{username}@#{domain}"
      def acct(username) = "acct:#{handle(username)}"

      # True when a URI addresses this instance. Scheme, host AND port must all
      # match: accepting a URI that differs only by port would let a second
      # instance on the same host impersonate our actors.
      def local_uri?(uri)
        parsed = URI.parse(uri.to_s)
        return false unless parsed.scheme && SUPPORTED_PROTOCOLS.include?(parsed.scheme)
        return false if parsed.userinfo.present? || parsed.query.present? || parsed.fragment.present?

        parsed.scheme == scheme && parsed.host == host && parsed.port == port
      rescue URI::InvalidURIError, URI::InvalidComponentError
        false
      end

      # Escape hatch for the Tier-2 local ring, where instances address each
      # other by Docker network alias over plain HTTP. Never enable in production:
      # it disables the SSRF guard's private-range checks.
      def allow_private_ips? = @allow_private_ips

      def secure? = protocol == "https"

      def to_s = base_url

      private

      def parse_base_url(value)
        uri = URI.parse(value.to_s.strip.chomp("/"))

        raise InvalidBaseUrl, "FEDERATION_BASE_URL must be an absolute HTTP(S) URI" if uri.host.blank?
        raise InvalidBaseUrl, "FEDERATION_BASE_URL must use http or https" unless SUPPORTED_PROTOCOLS.include?(uri.scheme)
        raise InvalidBaseUrl, "FEDERATION_BASE_URL must not contain credentials" if uri.userinfo.present?
        raise InvalidBaseUrl, "FEDERATION_BASE_URL must not contain a query or fragment" if uri.query.present? || uri.fragment.present?
        raise InvalidBaseUrl, "FEDERATION_BASE_URL must not contain a path" if uri.path.present? && uri.path != "/"
        raise InvalidBaseUrl, "FEDERATION_BASE_URL must not be opaque" if uri.opaque.present?
        raise InvalidBaseUrl, "FEDERATION_BASE_URL has an invalid port" unless uri.port.between?(1, 65_535)

        uri
      rescue URI::InvalidURIError, URI::InvalidComponentError => e
        raise InvalidBaseUrl, "FEDERATION_BASE_URL is not a valid URI: #{e.message}"
      end

      def normalize_protocol(value)
        protocol = value.to_s.downcase
        return protocol if SUPPORTED_PROTOCOLS.include?(protocol)

        raise InvalidBaseUrl, "FEDERATION_PROTOCOL must be http or https"
      end
    end
  end
end
