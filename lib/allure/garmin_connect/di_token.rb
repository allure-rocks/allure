# frozen_string_literal: true

require "base64"
require "json"

module Allure
  module GarminConnect
    # Exchanges an SSO service ticket for the Garmin Connect mobile
    # application's "DI" OAuth2 token, and refreshes it
    # (docs/dev/REMOTE-IMPORTS.md, §7.3).
    class DiToken
      CLIENT_IDS = %w[
        GARMIN_CONNECT_MOBILE_ANDROID_DI_2025Q2
        GARMIN_CONNECT_MOBILE_ANDROID_DI_2024Q4
        GARMIN_CONNECT_MOBILE_ANDROID_DI
        GARMIN_CONNECT_MOBILE_IOS_DI
      ].freeze
      SERVICE_TICKET_GRANT = "https://connectapi.garmin.com/di-oauth2-service/oauth/grant/service_ticket"
      REFRESH_MARGIN = 15 * 60

      Token = Data.define(:access_token, :refresh_token, :client_id, :expires_at) do
        def expires_soon?(now: Time.now, margin: REFRESH_MARGIN)
          !expires_at.nil? && now >= expires_at - margin
        end

        def self.from_h(hash)
          hash = hash.transform_keys(&:to_s)
          expires_at = hash["expires_at"] && Time.at(Integer(hash["expires_at"]))
          new(access_token: hash.fetch("access_token"), refresh_token: hash["refresh_token"],
              client_id: hash.fetch("client_id"), expires_at:)
        end

        def to_h
          super.merge(expires_at: expires_at&.to_i)
        end
      end

      # Unverified claims of a JWT (Garmin holds the key). An `alg: none`
      # header or a malformed token gives nil.
      def self.claims(jwt)
        header, payload = jwt.to_s.split(".", 3)
        return nil if header.nil? || payload.nil?

        return nil if decode_segment(header)&.fetch("alg", nil).to_s.casecmp?("none")

        decode_segment(payload)
      end

      def self.decode_segment(segment)
        decoded = JSON.parse(Base64.urlsafe_decode64(segment + ("=" * (-segment.length % 4))))
        decoded.is_a?(Hash) ? decoded : nil
      rescue ArgumentError, JSON::ParserError
        nil
      end

      attr_reader :region

      def initialize(region: Region.new)
        @region = region
      end

      def exchange(ticket:, service_url:)
        failures = []
        CLIENT_IDS.each do |client_id|
          response = http.post_form(region.di_token_url,
                                    headers: token_headers(client_id, accept: "application/json,text/html;q=0.9,*/*;q=0.8"),
                                    form: {
                                      client_id:, service_ticket: ticket,
                                      grant_type: SERVICE_TICKET_GRANT, service_url:
                                    })
          raise Error::RateLimited, "DI token exchange: HTTP 429" if response.status == 429

          token = response.success? && build(response.json, client_id:, refresh_token: nil)
          return token if token

          failures << "#{client_id}: HTTP #{response.status}"
        end
        raise Error::TokenRejected, "DI token exchange failed (#{failures.join(', ')})"
      end

      def refresh(token)
        raise Error::TokenRejected, "no DI refresh token" if token.refresh_token.to_s.empty?

        response = http.post_form(region.di_token_url,
                                  headers: token_headers(token.client_id, accept: "application/json"),
                                  form: {
                                    grant_type: "refresh_token", client_id: token.client_id,
                                    refresh_token: token.refresh_token
                                  })
        raise Error::RateLimited, "DI token refresh: HTTP 429" if response.status == 429
        raise Error::Unavailable, "DI token refresh: HTTP #{response.status}" if response.status >= 500

        refreshed = response.success? && build(response.json, client_id: token.client_id, refresh_token: token.refresh_token)
        refreshed || raise(Error::TokenRejected, "DI token refresh refused: HTTP #{response.status}")
      end

      private

      def build(json, client_id:, refresh_token:)
        return nil unless json.is_a?(Hash) && !json["access_token"].to_s.empty?

        access_token = json["access_token"].to_s
        claims = self.class.claims(access_token) || {}
        exp = claims["exp"]
        expires_at = Time.at(exp.to_i) if exp.is_a?(Numeric) && exp.to_f.finite?
        Token.new(access_token:,
                  refresh_token: json["refresh_token"].to_s.empty? ? refresh_token : json["refresh_token"].to_s,
                  client_id: claims["client_id"].to_s.empty? ? client_id : claims["client_id"].to_s,
                  expires_at:)
      end

      def token_headers(client_id, accept:)
        NativeHeaders.call("Authorization" => NativeHeaders.basic_auth(client_id),
                           "Accept" => accept, "Cache-Control" => "no-cache")
      end

      def http
        Http.new(allowed_hosts: region.hosts)
      end
    end
  end
end
