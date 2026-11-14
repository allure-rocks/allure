# frozen_string_literal: true

require "net/http"
require "openssl"
require "timeout"
require "uri"

module Federation
  module Transport
    class Client
      class ResponseTooLarge < StandardError; end
      class ResponseTimeout < StandardError; end
      class NetworkError < StandardError; end
      class TooManyRedirects < StandardError; end
      class UnsafeRedirect < StandardError; end

      Response = Data.define(:status, :headers, :body, :uri)
      MAX_RESPONSE_BYTES = 1.megabyte
      MAX_REDIRECTS = 3
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 10
      WRITE_TIMEOUT = 5
      TOTAL_TIMEOUT = 15

      def initialize(config: Allure::Federation.config, guard: nil, http_factory: nil)
        @guard = guard || SsrfGuard.new(config: config)
        @http_factory = http_factory || ->(uri) { Net::HTTP.new(uri.host, uri.port) }
      end

      def get(url, headers: {}, max_bytes: MAX_RESPONSE_BYTES, read_timeout: READ_TIMEOUT, total_timeout: TOTAL_TIMEOUT,
              max_redirects: MAX_REDIRECTS)
        request(method: :get, url:, headers:, max_bytes:, read_timeout:, total_timeout:, max_redirects:)
      end

      def post(url, body:, headers: {}, max_bytes: MAX_RESPONSE_BYTES, read_timeout: READ_TIMEOUT, total_timeout: TOTAL_TIMEOUT,
               max_redirects: MAX_REDIRECTS)
        request(method: :post, url:, body:, headers:, max_bytes:, read_timeout:, total_timeout:, max_redirects:)
      end

      def validate_url(url) = @guard.validate!(url)

      # `max_redirects: 0` refuses any redirect (webhooks, PLAN_API.md §11.4).
      #
      # `total_timeout` is one deadline for the whole exchange: every hop of a
      # redirect chain and every address resolution spend from it, so a slow
      # peer cannot hold the calling thread for (redirects + 1) × the timeout.
      def request(method:, url:, body: "", headers: {}, max_bytes: MAX_RESPONSE_BYTES,
                  read_timeout: READ_TIMEOUT, total_timeout: TOTAL_TIMEOUT, max_redirects: MAX_REDIRECTS)
        current_url = url.to_s
        redirects = 0
        deadline = monotonic_now + total_timeout

        loop do
          resolved = within(deadline) { @guard.validate!(current_url) }
          response = perform_request(
            method:, resolved:, body:, headers:,
            max_bytes:, read_timeout:, deadline:
          )
          return response unless redirect?(response.status)
          raise TooManyRedirects if redirects >= max_redirects

          location = response.headers["location"]
          raise UnsafeRedirect if location.blank?

          next_url = URI.join(resolved.uri.to_s, location).to_s
          if resolved.uri.scheme == "https" && URI.parse(next_url).scheme != "https"
            raise UnsafeRedirect, "redirect downgraded HTTPS"
          end
          current_url = next_url
          redirects += 1
        end
      rescue URI::InvalidURIError, URI::InvalidComponentError
        raise SsrfGuard::UnsafeUri, "invalid redirect URI"
      end

      private

      def perform_request(method:, resolved:, body:, headers:, max_bytes:, read_timeout:, deadline:)
        remaining = remaining!(deadline)
        uri = resolved.uri
        http = @http_factory.call(uri)
        http.ipaddr = resolved.addresses.first.to_s if http.respond_to?(:ipaddr=)
        http.use_ssl = uri.scheme == "https"
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER if http.use_ssl?
        http.open_timeout = [ OPEN_TIMEOUT, remaining ].min
        http.read_timeout = [ read_timeout, remaining ].min
        http.write_timeout = WRITE_TIMEOUT if http.respond_to?(:write_timeout=)
        request = Net::HTTP.const_get(method.to_s.capitalize).new(uri.request_uri)
        headers.each { |name, value| request[name] = value }
        request.body = body.to_s if method.to_sym == :post
        response_body = +""
        response = Timeout.timeout(remaining, ResponseTimeout) do
          http.request(request) do |http_response|
            http_response.read_body do |chunk|
              response_body << chunk
              raise ResponseTooLarge if response_body.bytesize > max_bytes
            end
          end
        end
        Response.new(response.code.to_i, response.each_header.to_h, response_body.b, uri)
      rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error, IOError, SystemCallError, OpenSSL::SSL::SSLError => error
        raise NetworkError, error.message
      end

      def within(deadline, &)
        Timeout.timeout(remaining!(deadline), ResponseTimeout, &)
      end

      def remaining!(deadline)
        remaining = deadline - monotonic_now
        raise ResponseTimeout, "request deadline exceeded" unless remaining.positive?

        remaining
      end

      def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      def redirect?(status) = [ 301, 302, 303, 307, 308 ].include?(status.to_i)
    end
  end
end
