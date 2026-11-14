# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "uri"

module Allure
  module Funding
    module Stripe
      # Small, fixed-host Stripe REST client. No provider payload is logged or
      # retained, responses are bounded, and redirects are never followed.
      class Client
        HOST = "api.stripe.com"
        BASE_URL = "https://#{HOST}".freeze
        API_VERSION = "2024-06-20"
        OPEN_TIMEOUT = 5
        READ_TIMEOUT = 15
        MAX_BODY_BYTES = 2 * 1024 * 1024
        TRANSPORT_ERRORS = [
          IOError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError,
          Net::HTTPBadResponse, Net::ProtocolError, EOFError
        ].freeze

        def initialize(secret_key: Config.stripe_secret_key)
          @secret_key = secret_key.to_s
          raise Allure::Funding::Providers::ProviderError, "Stripe API key is not configured" if @secret_key.empty?
        end

        def get(path, params = {})
          uri = build_uri(path, params)
          perform(Net::HTTP::Get.new(uri), uri)
        end

        def post_form(path, form)
          uri = build_uri(path)
          request = Net::HTTP::Post.new(uri)
          request.body = URI.encode_www_form(form)
          request["Content-Type"] = "application/x-www-form-urlencoded"
          perform(request, uri)
        end

        def delete(path)
          uri = build_uri(path)
          perform(Net::HTTP::Delete.new(uri), uri)
        end

        private

        def build_uri(path, params = {})
          uri = URI.join(BASE_URL, path)
          raise ArgumentError, "invalid Stripe API URL" unless uri.is_a?(URI::HTTPS) && uri.host == HOST

          uri.query = URI.encode_www_form(params) if params.any?
          uri
        end

        def perform(request, uri)
          request["Authorization"] = "Bearer #{@secret_key}"
          request["Stripe-Version"] = API_VERSION
          request["Accept"] = "application/json"
          request["User-Agent"] = "Allure instance funding"

          Net::HTTP.start(uri.hostname, uri.port, use_ssl: true,
                          open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
            http.request(request) do |response|
              body = read_body(response)
              status = response.code.to_i
              unless status.between?(200, 299)
                raise Error.new("Stripe API answered HTTP #{status}", status:)
              end

              parsed = JSON.parse(body)
              return parsed if parsed.is_a?(Hash)

              raise Error, "Stripe API returned a non-object response"
            end
          end
        rescue Error
          raise
        rescue JSON::ParserError
          raise Error, "Stripe API returned invalid JSON"
        rescue *TRANSPORT_ERRORS => error
          raise Error, "Stripe API transport failure: #{error.class.name}"
        end

        def read_body(response)
          body = +""
          response.read_body do |chunk|
            body << chunk
            raise Error, "Stripe API response is too large" if body.bytesize > MAX_BODY_BYTES
          end
          body
        end
      end
    end
  end
end
