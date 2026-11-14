# frozen_string_literal: true

require "json"
require "net/http"
require "timeout"
require "uri"

module Allure
  module Elevation
    # Thin OpenTopoData elevation client.
    #
    # Framework-independent: Net::HTTP only, no Active Record and no Rails.
    # `elevations` returns one value per requested location, aligned with the
    # input; a location outside every dataset is nil. Provider and transport
    # failures are retryable (`UnavailableError`); a request the provider
    # rejects is not (`InvalidRequestError`).
    #
    # OpenTopoData answers `GET /v1/{dataset}?locations=lat,lon|lat,lon` with a
    # Google-Elevation-compatible document. The public instance caps a request
    # at 100 locations, so callers chunk; this client enforces the same bound.
    class OpenTopoData
      class Error < StandardError; end
      class UnavailableError < Error; end
      class InvalidRequestError < Error; end

      MAX_LOCATIONS = 100
      DEFAULT_INTERPOLATION = "bilinear"
      USER_AGENT = "Allure (elevation enrichment)"
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 10
      TOTAL_TIMEOUT = 15
      MAX_RESPONSE_BYTES = 256 * 1024
      COORDINATE_PRECISION = "%.6f"

      attr_reader :base_url, :dataset, :interpolation

      def initialize(base_url:, dataset:, interpolation: DEFAULT_INTERPOLATION)
        @base_url = base_url.to_s
        @dataset = dataset.to_s
        @interpolation = interpolation.to_s
      end

      # `locations` is an ordered array of `[latitude, longitude]` pairs.
      # Returns an array of Float or nil in the same order.
      def elevations(locations)
        locations = Array(locations)
        if locations.length > MAX_LOCATIONS
          raise ArgumentError, "at most #{MAX_LOCATIONS} locations per request"
        end
        return [] if locations.empty?

        parse_results(request_json(locations), locations.length)
      end

      private

      def request_json(locations)
        uri = URI.parse("#{base_url.chomp("/")}/v1/#{dataset}")
        uri.query = URI.encode_www_form(locations: encode_locations(locations), interpolation:)
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = USER_AGENT
        request["Accept"] = "application/json"

        Timeout.timeout(TOTAL_TIMEOUT) do
          Net::HTTP.start(
            uri.hostname, uri.port,
            use_ssl: uri.scheme == "https",
            open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT
          ) do |http|
            http.request(request) do |response|
              body = read_body(response)
              return parse_json(body) if response.is_a?(Net::HTTPSuccess)
              return raise_unavailable(body, response) if response.code == "429"

              raise InvalidRequestError, error_message(body, response) if response.is_a?(Net::HTTPClientError)

              raise UnavailableError, error_message(body, response)
            end
          end
        end
      rescue InvalidRequestError, UnavailableError
        raise
      rescue StandardError => error
        raise UnavailableError, error.message
      end

      def encode_locations(locations)
        locations.map { |latitude, longitude| format("#{COORDINATE_PRECISION},#{COORDINATE_PRECISION}", latitude, longitude) }.join("|")
      end

      def parse_json(body)
        JSON.parse(body)
      rescue JSON::ParserError => error
        raise UnavailableError, "malformed elevation response: #{error.message}"
      end

      def parse_results(json, expected)
        status = json["status"].to_s
        raise InvalidRequestError, error_message_from(json) if status == "INVALID_REQUEST"
        raise UnavailableError, error_message_from(json) unless status == "OK"

        results = json["results"]
        unless results.is_a?(Array) && results.length == expected
          raise UnavailableError, "malformed elevation response: expected #{expected} results"
        end

        results.map { |result| elevation_value(result) }
      end

      def elevation_value(result)
        raise UnavailableError, "malformed elevation response: missing result" unless result.is_a?(Hash)

        value = result["elevation"]
        return nil if value.nil?
        return value.to_f if value.is_a?(Numeric) && value.to_f.finite?

        raise UnavailableError, "malformed elevation response: non-numeric elevation"
      end

      def read_body(response)
        body = +""
        response.read_body do |chunk|
          if body.bytesize + chunk.bytesize > MAX_RESPONSE_BYTES
            raise UnavailableError, "Elevation response exceeds size limit"
          end

          body << chunk
        end
        body
      end

      def raise_unavailable(body, response)
        raise UnavailableError, error_message(body, response)
      end

      def error_message(body, response)
        json = JSON.parse(body)
        message = json["error"].to_s.strip
        return "Elevation provider returned HTTP #{response.code}" if message.empty?

        "Elevation provider error: #{message}"
      rescue JSON::ParserError
        "Elevation provider returned HTTP #{response.code}"
      end

      def error_message_from(json)
        message = json["error"].to_s.strip
        message.empty? ? "Elevation provider rejected the request" : "Elevation provider error: #{message}"
      end
    end
  end
end
