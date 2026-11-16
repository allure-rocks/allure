# frozen_string_literal: true

module Allure
  module GarminConnect
    # Authenticated calls to connectapi with the DI bearer
    # (docs/dev/REMOTE-IMPORTS.md–7.4). Refreshes the token when it expires
    # within 15 minutes and once after a 401; `token` is the current token.
    # Garmin rotates the refresh token on every refresh, so `on_refresh` is
    # called with the new token before any further request: the caller must
    # persist it there. At most one request per `min_interval` seconds.
    class Client
      ACTIVITY_PAGE_SIZE = 50
      MAX_ORIGINAL_BYTES = 64 * 1024 * 1024

      attr_reader :region, :token

      def initialize(token:, region: Region.new, di_token: nil, min_interval: 1.0, on_refresh: nil,
                     clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
                     sleeper: ->(seconds) { sleep(seconds) })
        @token = token
        @on_refresh = on_refresh
        @region = region
        @di_token = di_token || DiToken.new(region:)
        @min_interval = min_interval
        @clock = clock
        @sleeper = sleeper
        @last_request_at = nil
      end

      def social_profile
        get_json("/userprofile-service/socialProfile")
      end

      def activities(start: 0, limit: ACTIVITY_PAGE_SIZE, start_date: nil, end_date: nil)
        params = { start:, limit: }
        params[:startDate] = start_date.iso8601 if start_date
        params[:endDate] = end_date.iso8601 if end_date
        get_json("/activitylist-service/activities/search/activities", params:)
      end

      # The gear recorded on one activity (a list, usually of one item).
      def activity_gear(activity_id)
        get_json("/gear-service/gear/filterGear", params: { activityId: Integer(activity_id) })
      end

      # Every gear item of the account (`userProfilePk` is the social profile's
      # `profileId`).
      def gear(user_profile_pk)
        get_json("/gear-service/gear/filterGear", params: { userProfilePk: Integer(user_profile_pk) })
      end

      # Streams the original-file ZIP of one activity into `io`.
      def download_original(activity_id, io:, max_bytes: MAX_ORIGINAL_BYTES)
        id = Integer(activity_id)
        request("/download-service/files/activity/#{id}", accept: "*/*") do |http, url, headers|
          io.rewind
          io.truncate(0) if io.respond_to?(:truncate)
          http.download(url, io:, max_bytes:, headers:)
        end
        io.rewind
        io
      end

      private

      def get_json(path, params: {})
        response = request(path, accept: "application/json") do |http, url, headers|
          http.get(url, params:, headers:)
        end
        return {} if response.status == 204

        json = response.json
        raise Error::Unavailable, "#{path}: non-JSON answer" if json.nil?

        json
      end

      def request(path, accept:)
        refresh! if token.expires_soon?
        url = "#{region.connectapi_base}#{path}"
        response = nil
        2.times do |attempt|
          throttle
          response = yield(http, url, headers(accept))
          break unless response.status == 401 && attempt.zero?

          refresh!
        end
        check!(response, path)
        response
      end

      def check!(response, path)
        return if response.success?

        case response.status
        when 401, 403 then raise Error::TokenRejected, "#{path}: HTTP #{response.status}"
        when 404 then raise Error::NotFound, "#{path}: HTTP 404"
        when 429 then raise Error::RateLimited, "#{path}: HTTP 429"
        else raise Error::Unavailable, "#{path}: HTTP #{response.status}"
        end
      end

      def refresh!
        @token = @di_token.refresh(token)
        @on_refresh&.call(@token)
      end

      def headers(accept)
        NativeHeaders.call("Authorization" => "Bearer #{token.access_token}", "Accept" => accept)
      end

      def throttle
        now = @clock.call
        if @last_request_at
          wait = @min_interval - (now - @last_request_at)
          @sleeper.call(wait) if wait.positive?
        end
        @last_request_at = @clock.call
      end

      def http
        Http.new(allowed_hosts: region.hosts)
      end
    end
  end
end
