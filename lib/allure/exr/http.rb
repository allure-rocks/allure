# frozen_string_literal: true

require "net/http"
require "openssl"
require "time"
require "uri"

module Allure
  module Exr
    # A small HTTPS session over Net::HTTP for `account.exrgame.com`, with a
    # cookie jar that keeps each cookie's expiry. Framework-independent.
    #
    # The host is pinned, only HTTPS is spoken, redirects are never followed —
    # a redirect to the sign-in page is how the site says a session is gone —
    # every body is bounded, and requests are spaced by `min_interval`.
    class Http
      HOST = "account.exrgame.com"
      BASE_URL = "https://#{HOST}".freeze

      Response = Data.define(:status, :body, :location) do
        def success? = status.between?(200, 299)
        def redirect? = status.between?(300, 399) && !location.nil?
      end

      Cookie = Data.define(:name, :value, :expires_at)

      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 20
      MAX_BODY_BYTES = 1024 * 1024
      MIN_INTERVAL = 1.0
      TRANSPORT_ERRORS = [
        IOError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError,
        Net::HTTPBadResponse, Net::ProtocolError, EOFError
      ].freeze
      USER_AGENT = "Allure remote import (+https://exrgame.com account export)"

      def initialize(cookies: [], min_interval: MIN_INTERVAL, sleeper: ->(seconds) { sleep(seconds) },
                     clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        @jar = Array(cookies).to_h { |cookie| [ cookie.name, cookie ] }
        @min_interval = min_interval
        @sleeper = sleeper
        @clock = clock
        @last_request_at = nil
      end

      def cookies = @jar.values

      def cookie(name) = @jar[name]

      def get(path, headers: {})
        uri = build_uri(path)
        perform(Net::HTTP::Get.new(uri), uri, headers)
      end

      def post_form(path, form:, headers: {})
        uri = build_uri(path)
        request = Net::HTTP::Post.new(uri)
        request.body = URI.encode_www_form(form)
        perform(request, uri, { "Content-Type" => "application/x-www-form-urlencoded" }.merge(headers))
      end

      # Streams a successful body into `io`, up to `max_bytes`; any other
      # answer is read into the response body as usual.
      def download(path, io:, max_bytes:)
        uri = build_uri(path)
        perform(Net::HTTP::Get.new(uri), uri, {}, sink: io, max_bytes:)
      end

      private

      def build_uri(path)
        uri = URI.join(BASE_URL, path)
        raise ArgumentError, "EXR requests must use HTTPS" unless uri.is_a?(URI::HTTPS)
        raise ArgumentError, "host #{uri.host} is not the EXR account site" unless uri.host.to_s.downcase == HOST

        uri
      end

      def perform(request, uri, headers, sink: nil, max_bytes: MAX_BODY_BYTES)
        throttle
        request["User-Agent"] = USER_AGENT
        request["Accept-Language"] = "en"
        headers.each { |name, value| request[name] = value }
        request["Cookie"] = cookie_header unless @jar.empty?

        Net::HTTP.start(uri.hostname, uri.port, use_ssl: true,
                        open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
          http.request(request) do |response|
            store_cookies(response)
            body = read_body(response, sink:, max_bytes:)
            return Response.new(status: response.code.to_i, body:, location: response["location"])
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

      def store_cookies(response)
        Array(response.get_fields("set-cookie")).each do |line|
          pair, *attributes = line.split(";")
          name, value = pair.to_s.split("=", 2).map { |part| part.to_s.strip }
          next if name.nil? || name.empty?

          expires_at = expiry(attributes)
          if value.to_s.empty? || (expires_at && expires_at <= Time.now)
            @jar.delete(name)
          else
            @jar[name] = Cookie.new(name:, value:, expires_at:)
          end
        end
      end

      def expiry(attributes)
        options = attributes.to_h do |attribute|
          key, value = attribute.split("=", 2).map { |part| part.to_s.strip }
          [ key.downcase, value ]
        end
        return Time.now + Integer(options["max-age"]) if options["max-age"]&.match?(/\A-?\d+\z/)

        options["expires"] && Time.httpdate(options["expires"].sub(/(\d{2})-(\w{3})-(\d{4})/, '\1 \2 \3'))
      rescue ArgumentError
        nil
      end

      def cookie_header
        @jar.values.map { |cookie| "#{cookie.name}=#{cookie.value}" }.join("; ")
      end
    end
  end
end
