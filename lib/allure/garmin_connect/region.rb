# frozen_string_literal: true

module Allure
  module GarminConnect
    # The hosts of one Garmin region. Accounts created in China live on
    # garmin.cn and do not exist in the garmin.com user database.
    class Region
      DOMAINS = { "com" => "garmin.com", "cn" => "garmin.cn" }.freeze

      attr_reader :key, :domain

      def initialize(key = "com")
        @key = key.to_s
        @domain = DOMAINS.fetch(@key) { raise ArgumentError, "unknown Garmin region #{key.inspect}" }
      end

      def sso_base = "https://sso.#{domain}"

      def connectapi_base = "https://connectapi.#{domain}"

      def di_token_url = "https://diauth.#{domain}/di-oauth2-service/oauth/token"

      def ios_service_url = "https://mobile.integration.#{domain}/gcm/ios"

      def portal_service_url = "https://connect.#{domain}/app"

      def hosts
        [ sso_base, connectapi_base, di_token_url ].map { |url| URI.parse(url).host }
      end
    end
  end
end
