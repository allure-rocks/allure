# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "uri"

module Allure
  module Withings
    # A small HTTPS form client for `scalews.withings.net`, the private API of
    # the Health Mate application (docs/dev/REMOTE-IMPORTS.md). The host is
    # pinned, only HTTPS is spoken, redirects are never followed — the API
    # answers JSON, so a redirect is a misrouted call — every body is bounded,
    # and requests are spaced by `min_interval`. Framework-independent.
    class Http
      HOST = "scalews.withings.net"
      BASE_URL = "https://#{HOST}".freeze

      Response = Data.define(:status, :body) do
        def success? = status.between?(200, 299)

        # Parsed JSON, or nil when the body is not JSON.
        def json
          JSON.parse(body)
        rescue JSON::ParserError
          nil
        end
      end

      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 20
      MAX_BODY_BYTES = 1024 * 1024
      MIN_INTERVAL = 1.0
      TRANSPORT_ERRORS = [
        IOError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError,
        Net::HTTPBadResponse, Net::ProtocolError, EOFError
      ].freeze
      # The form identifies the iOS Health Mate application (`appname`,
      # `appliver`); the user agent follows it, as the application's own
      # requests would.
      USER_AGENT = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) " \
                   "AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"

      def initialize(min_interval: MIN_INTERVAL,
                     sleeper: ->(seconds) { sleep(seconds) },
                     clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        @min_interval = min_interval
        @sleeper = sleeper
        @clock = clock
        @last_request_at = nil
      end

      def post_form(path, form:, headers: {})
        uri = build_uri(path)
        request = Net::HTTP::Post.new(uri)
        request.body = URI.encode_www_form(form)
        perform(request, uri, { "Content-Type" => "application/x-www-form-urlencoded" }.merge(headers))
      end

      private

      def build_uri(path)
        uri = URI.join(BASE_URL, path)
        raise ArgumentError, "Withings requests must use HTTPS" unless uri.is_a?(URI::HTTPS)
        raise ArgumentError, "host #{uri.host} is not the Withings API" unless uri.host.to_s.downcase == HOST

        uri
      end

      def perform(request, uri, headers)
        throttle
        request["User-Agent"] = USER_AGENT
        headers.each { |name, value| request[name] = value }

        Net::HTTP.start(uri.hostname, uri.port, use_ssl: true,
                        open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
          http.request(request) do |response|
            body = +""
            total = 0
            response.read_body do |chunk|
              total += chunk.bytesize
              raise Error::Unavailable, "response exceeds #{MAX_BODY_BYTES} bytes" if total > MAX_BODY_BYTES

              body << chunk
            end
            return Response.new(status: response.code.to_i, body:)
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
    end
  end
end
