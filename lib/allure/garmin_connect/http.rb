# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "uri"

module Allure
  module GarminConnect
    # A small HTTPS session over Net::HTTP with the cookie jar the SSO steps
    # share (sign-in page → login → MFA). Framework-independent.
    #
    # Hosts are pinned to the region's, only HTTPS is spoken, a GET follows at
    # most three redirects on the pinned hosts, and every body is bounded.
    class Http
      Response = Data.define(:status, :body, :headers) do
        def success? = status.between?(200, 299)

        # Parsed JSON, or nil when the body is not JSON (a Cloudflare page).
        def json
          JSON.parse(body)
        rescue JSON::ParserError
          nil
        end
      end

      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 30
      MAX_BODY_BYTES = 1024 * 1024
      MAX_REDIRECTS = 3
      TRANSPORT_ERRORS = [
        IOError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError,
        Net::HTTPBadResponse, Net::ProtocolError, EOFError
      ].freeze

      attr_reader :cookies

      def initialize(allowed_hosts:, cookies: {})
        @allowed_hosts = Array(allowed_hosts).map(&:downcase).freeze
        @cookies = cookies.to_h.transform_keys(&:to_s).transform_values(&:to_s)
      end

      def get(url, params: {}, headers: {})
        uri = build_uri(url, params)
        MAX_REDIRECTS.succ.times do
          response = perform(Net::HTTP::Get.new(uri), uri, headers)
          return response unless (300..399).cover?(response.status) && response.headers["location"]

          uri = build_uri(URI.join(uri.to_s, response.headers["location"]).to_s, {})
        end
        raise Error::Unavailable, "too many redirects"
      end

      def post_json(url, params: {}, headers: {}, body: {})
        uri = build_uri(url, params)
        request = Net::HTTP::Post.new(uri)
        request.body = JSON.generate(body)
        perform(request, uri, { "Content-Type" => "application/json" }.merge(headers))
      end

      def post_form(url, headers: {}, form: {})
        uri = build_uri(url, {})
        request = Net::HTTP::Post.new(uri)
        request.body = URI.encode_www_form(form)
        perform(request, uri, { "Content-Type" => "application/x-www-form-urlencoded" }.merge(headers))
      end

      # Streams a successful body into `io`, up to `max_bytes`. Returns the
      # response with an empty body and the number of bytes in `headers`.
      def download(url, io:, max_bytes:, params: {}, headers: {})
        uri = build_uri(url, params)
        perform(Net::HTTP::Get.new(uri), uri, headers, sink: io, max_bytes:)
      end

      private

      def build_uri(url, params)
        uri = URI.parse(url)
        raise ArgumentError, "Garmin requests must use HTTPS" unless uri.is_a?(URI::HTTPS)
        raise ArgumentError, "host #{uri.host} is not a Garmin host" unless @allowed_hosts.include?(uri.host.to_s.downcase)

        unless params.empty?
          query = URI.encode_www_form(params)
          uri.query = [ uri.query, query ].compact.reject(&:empty?).join("&")
        end
        uri
      end

      def perform(request, uri, headers, sink: nil, max_bytes: MAX_BODY_BYTES)
        headers.each { |name, value| request[name] = value }
        request["Cookie"] = cookie_header unless @cookies.empty?

        Net::HTTP.start(uri.hostname, uri.port, use_ssl: true,
                        open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
          http.request(request) do |response|
            store_cookies(response)
            body = read_body(response, sink:, max_bytes:)
            return Response.new(status: response.code.to_i, body:, headers: header_hash(response))
          end
        end
      rescue Error
        raise
      rescue *TRANSPORT_ERRORS => error
        raise Error::Unavailable, "#{uri.host}: #{error.class.name}"
      end

      def read_body(response, sink:, max_bytes:)
        stream_to = sink && response.code.to_i.between?(200, 299) ? sink : nil
        body = +""
        total = 0
        response.read_body do |chunk|
          total += chunk.bytesize
          raise Error::Unavailable, "response exceeds #{max_bytes} bytes" if total > (stream_to ? max_bytes : MAX_BODY_BYTES)

          stream_to ? stream_to.write(chunk) : body << chunk
        end
        body
      end

      def header_hash(response)
        response.each_header.to_h
      end

      def store_cookies(response)
        Array(response.get_fields("set-cookie")).each do |line|
          pair = line.split(";", 2).first.to_s
          name, value = pair.split("=", 2).map { |part| part.to_s.strip }
          next if name.nil? || name.empty?

          expired = line.match?(/max-age=0\b/i) || value.to_s.empty?
          expired ? @cookies.delete(name) : @cookies[name] = value
        end
      end

      def cookie_header
        @cookies.map { |name, value| "#{name}=#{value}" }.join("; ")
      end
    end
  end
end
