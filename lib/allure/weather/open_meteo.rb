# frozen_string_literal: true

require "json"
require "net/http"
require "timeout"
require "uri"

module Allure
  module Weather
    # Thin Open-Meteo historical weather client (docs/dev/WEATHER.md).
    #
    # Framework-independent: Net::HTTP only. `hourly` asks one endpoint for the
    # hourly values of up to ten locations over a UTC date range and returns
    # one hash per location, aligned with the input, holding `time` (Unix
    # seconds) and one array per variable. Ten variables and ten locations keep
    # a request a single billed call.
    #
    # Transport failures, 429 and 5xx are retryable (`UnavailableError`); any
    # other rejection is not (`InvalidRequestError`).
    class OpenMeteo
      class Error < StandardError; end

      class UnavailableError < Error; end

      class InvalidRequestError < Error; end

      VARIABLES = %w[
        temperature_2m apparent_temperature relative_humidity_2m precipitation weather_code
        cloud_cover surface_pressure wind_speed_10m wind_direction_10m wind_gusts_10m
      ].freeze
      MAX_LOCATIONS = 10
      PATHS = { forecast: "/v1/forecast", archive: "/v1/archive" }.freeze
      USER_AGENT = "Allure (weather enrichment)"
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 15
      TOTAL_TIMEOUT = 20
      MAX_RESPONSE_BYTES = 2 * 1024 * 1024

      Location = Data.define(:latitude, :longitude, :elevation)

      attr_reader :forecast_url, :archive_url

      def initialize(forecast_url:, archive_url:, api_key: nil)
        @forecast_url = forecast_url.to_s
        @archive_url = archive_url.to_s
        @api_key = api_key
      end

      def hourly(endpoint:, locations:, start_date:, end_date:)
        locations = Array(locations)
        raise ArgumentError, "at most #{MAX_LOCATIONS} locations per request" if locations.length > MAX_LOCATIONS
        return [] if locations.empty?

        json = request_json(uri_for(endpoint.to_sym, locations, start_date, end_date))
        parse(json, locations.length)
      end

      def uri_for(endpoint, locations, start_date, end_date)
        base = endpoint == :archive ? archive_url : forecast_url
        path = PATHS.fetch(endpoint) { raise ArgumentError, "unknown endpoint: #{endpoint.inspect}" }
        uri = URI.parse("#{base.chomp("/")}#{path}")
        params = {
          latitude: locations.map { |location| format("%.1f", location.latitude) }.join(","),
          longitude: locations.map { |location| format("%.1f", location.longitude) }.join(","),
          start_date: start_date.iso8601,
          end_date: end_date.iso8601,
          hourly: VARIABLES.join(","),
          timezone: "GMT",
          timeformat: "unixtime",
          wind_speed_unit: "ms",
          temperature_unit: "celsius",
          precipitation_unit: "mm"
        }
        # The recorded elevation keeps the provider's downscaling right on a
        # coarsened position; without it for every location, the provider's
        # own terrain model is used for all of them.
        elevations = locations.map(&:elevation)
        params[:elevation] = elevations.map { |value| value.round.to_s }.join(",") if elevations.all?
        params[:apikey] = @api_key if @api_key
        uri.query = URI.encode_www_form(params)
        uri
      end

      private

      def request_json(uri)
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = USER_AGENT
        request["Accept"] = "application/json"

        Timeout.timeout(TOTAL_TIMEOUT) do
          Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
                                                  open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
            http.request(request) do |response|
              body = read_body(response)
              return parse_json(body) if response.is_a?(Net::HTTPSuccess)

              message = error_message(body, response)
              if response.code == "429" || response.is_a?(Net::HTTPServerError)
                raise UnavailableError, message
              end

              raise InvalidRequestError, message
            end
          end
        end
      rescue Error
        raise
      rescue StandardError => error
        raise UnavailableError, error.message
      end

      def parse(json, expected)
        items = json.is_a?(Array) ? json : [ json ]
        raise UnavailableError, "malformed weather response: expected #{expected} locations" unless items.length == expected

        items.map { |item| parse_location(item) }
      end

      def parse_location(item)
        hourly = item.is_a?(Hash) ? item["hourly"] : nil
        raise UnavailableError, "malformed weather response: missing hourly values" unless hourly.is_a?(Hash)

        times = hourly["time"]
        raise UnavailableError, "malformed weather response: missing times" unless times.is_a?(Array)

        result = { "time" => times.map { |time| Integer(time) } }
        VARIABLES.each do |variable|
          values = hourly[variable]
          values = Array.new(times.length) unless values.is_a?(Array) && values.length == times.length
          result[variable] = values.map { |value| value.is_a?(Numeric) && value.to_f.finite? ? value.to_f : nil }
        end
        result
      rescue ArgumentError, TypeError
        raise UnavailableError, "malformed weather response: non-numeric time"
      end

      def parse_json(body)
        JSON.parse(body)
      rescue JSON::ParserError => error
        raise UnavailableError, "malformed weather response: #{error.message}"
      end

      def read_body(response)
        body = +""
        response.read_body do |chunk|
          raise UnavailableError, "weather response exceeds size limit" if body.bytesize + chunk.bytesize > MAX_RESPONSE_BYTES

          body << chunk
        end
        body
      end

      def error_message(body, response)
        reason = JSON.parse(body)["reason"].to_s.strip
        reason.empty? ? "Weather provider returned HTTP #{response.code}" : "Weather provider error: #{reason}"
      rescue JSON::ParserError, NoMethodError, TypeError
        "Weather provider returned HTTP #{response.code}"
      end
    end
  end
end
