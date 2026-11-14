# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "time"
require "uri"

module Allure
  module Zwift
    # A small HTTPS client for the two hosts of Zwift's mobile API
    # (PLAN_REMOTE_IMPORTS.md §7d): `secure.zwift.com` for the Keycloak token
    # endpoint and `us-or-rly101.zwift.com` for the read API. The FIT files
    # come from Zwift's own S3 bucket, whose name the API supplies; only a
    # safe bucket name and key are accepted, so a hostile answer can never
    # turn the download into a request to another host.
    #
    # Only HTTPS is spoken, redirects are never followed, every body is
    # bounded, and requests are spaced by `min_interval`. Framework
    # independent.
    class Http
      AUTH_HOST = "secure.zwift.com"
      AUTH_BASE_URL = "https://#{AUTH_HOST}".freeze
      API_HOST = "us-or-rly101.zwift.com"
      API_BASE_URL = "https://#{API_HOST}".freeze
      S3_SUFFIX = ".s3.amazonaws.com"

      # The neutral agent is tried first. Zwift has been observed refusing
      # some generic agents outright; only a 403 switches to the mobile
      # application's own agent, which is a header, never a TLS fingerprint.
      # The neutral agent was accepted on 2026-11-05.
      USER_AGENT = "Allure remote import (+https://allure.rocks)"
      MOBILE_USER_AGENT = "Zwift/115 CFNetwork/1335.0.3 Darwin/21.6.0"

      Response = Data.define(:status, :body, :location, :retry_after) do
        def success? = status.between?(200, 299)

        def redirect? = status.between?(300, 399) && !location.nil?

        # Parsed JSON, or nil when the body is not JSON.
        def json
          JSON.parse(body)
        rescue JSON::ParserError
          nil
        end
      end

      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 60
      MAX_BODY_BYTES = 1024 * 1024
      MIN_INTERVAL = 1.0
      TRANSPORT_ERRORS = [
        IOError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError,
        Net::HTTPBadResponse, Net::ProtocolError, EOFError
      ].freeze

      BUCKET_PATTERN = /\A[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]\z/
      # Zwift's own keys are UUID-like or path-like; anything else is refused
      # rather than escaped into a different request.
      KEY_PATTERN = %r{\A[A-Za-z0-9][A-Za-z0-9._/-]*\z}

      attr_reader :user_agent, :user_agent_fallback_status

      def initialize(user_agent: USER_AGENT, fallback_user_agent: MOBILE_USER_AGENT,
                     min_interval: MIN_INTERVAL, sleeper: ->(seconds) { sleep(seconds) },
                     clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        @user_agent = user_agent
        @fallback_user_agent = fallback_user_agent
        @min_interval = min_interval
        @sleeper = sleeper
        @clock = clock
        @last_request_at = nil
        @user_agent_fallback_status = nil
      end

      def get(path, params: nil, headers: {})
        uri = build_api_uri(path, params)
        response = perform(Net::HTTP::Get.new(uri), uri, headers)
        return response unless user_agent_fallback?(response)

        retry_with_mobile_agent(response, uri, headers) { Net::HTTP::Get.new(uri) }
      end

      def post_form(path, form:, headers: {})
        uri = build_auth_uri(path)
        body = URI.encode_www_form(form)
        build = lambda do
          request = Net::HTTP::Post.new(uri)
          request.body = body
          request["Content-Type"] = "application/x-www-form-urlencoded"
          request
        end
        response = perform(build.call, uri, headers)
        return response unless user_agent_fallback?(response)

        retry_with_mobile_agent(response, uri, headers, &build)
      end

      # Streams a successful body into `io`, up to `max_bytes`. The S3 object
      # takes no Authorization header and no cookie.
      def download_s3(bucket:, key:, io:, max_bytes:)
        uri = build_s3_uri(bucket, key)
        perform(Net::HTTP::Get.new(uri), uri, {}, sink: io, max_bytes:)
      end

      # Whether a bucket/key pair can be requested as an S3 object. The client
      # filters the URLs a provider announces with it before trying them.
      def safe_s3_object?(bucket, key)
        valid_bucket?(bucket) && valid_key?(key)
      end

      private

      def retry_with_mobile_agent(response, uri, headers)
        @user_agent_fallback_status = response.status
        @user_agent = @fallback_user_agent
        perform(yield, uri, headers)
      end

      def user_agent_fallback?(response)
        response.status == 403 && @fallback_user_agent && @user_agent != @fallback_user_agent
      end

      def build_api_uri(path, params)
        uri = URI.join(API_BASE_URL, path)
        raise ArgumentError, "Zwift API requests must use HTTPS" unless uri.is_a?(URI::HTTPS)
        raise ArgumentError, "host #{uri.host} is not the Zwift API" unless uri.host.to_s.downcase == API_HOST

        uri.query = URI.encode_www_form(params) if params && !params.empty?
        uri
      end

      def build_auth_uri(path)
        uri = URI.join(AUTH_BASE_URL, path)
        raise ArgumentError, "Zwift auth requests must use HTTPS" unless uri.is_a?(URI::HTTPS)
        raise ArgumentError, "host #{uri.host} is not the Zwift auth server" unless uri.host.to_s.downcase == AUTH_HOST

        uri
      end

      def build_s3_uri(bucket, key)
        raise ArgumentError, "unsafe S3 bucket name" unless valid_bucket?(bucket)
        raise ArgumentError, "unsafe S3 key" unless valid_key?(key)

        uri = URI::HTTPS.build(host: "#{bucket}#{S3_SUFFIX}", path: "/#{key}")
        raise ArgumentError, "unsafe S3 host" unless uri.host == "#{bucket}#{S3_SUFFIX}"

        uri
      end

      def valid_bucket?(bucket)
        name = bucket.to_s
        BUCKET_PATTERN.match?(name) && !name.include?("..")
      end

      def valid_key?(key)
        value = key.to_s
        KEY_PATTERN.match?(value) &&
          value.split("/").none? { |part| part == "." || part == ".." } &&
          !value.include?("\\")
      end

      def perform(request, uri, headers, sink: nil, max_bytes: MAX_BODY_BYTES)
        throttle
        request["User-Agent"] = @user_agent
        request["Accept-Language"] = "en"
        headers.each { |name, value| request[name] = value }

        Net::HTTP.start(uri.hostname, uri.port, use_ssl: true,
                        open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
          http.request(request) do |response|
            body = read_body(response, sink:, max_bytes:)
            return Response.new(status: response.code.to_i, body:, location: response["location"],
                                retry_after: retry_after(response))
          end
        end
      rescue Error
        raise
      rescue *TRANSPORT_ERRORS => error
        raise Error::Unavailable, "#{uri.host}: #{error.class.name}"
      end

      def throttle
        now = @clock.call
        wait = @last_request_at && (@min_interval - (now - @last_request_at))
        @sleeper.call(wait) if wait&.positive?
        @last_request_at = @clock.call
      end

      def read_body(response, sink:, max_bytes:)
        stream_to = sink && response.code.to_i.between?(200, 299) ? sink : nil
        limit = stream_to ? max_bytes : MAX_BODY_BYTES
        body = +""
        total = 0
        response.read_body do |chunk|
          total += chunk.bytesize
          raise Error::Unavailable, "response exceeds #{limit} bytes" if total > limit

          stream_to ? stream_to.write(chunk) : body << chunk
        end
        body
      end

      def retry_after(response)
        value = response["retry-after"].to_s.strip
        return nil if value.empty?
        return value.to_i if value.match?(/\A\d+\z/)

        [ Time.httpdate(value) - Time.now, 0 ].max.round
      rescue ArgumentError
        nil
      end
    end
  end
end
