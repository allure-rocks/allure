# frozen_string_literal: true

require "time"

module Allure
  module Zwift
    # Reads a Zwift account with a refresh token and nothing else
    # (docs/dev/REMOTE-IMPORTS.md): the profile, the activity list page by
    # page, and each activity's original FIT file. Only GETs are sent after
    # the token exchange. A refresh token the server rotates is handed to
    # `on_tokens` before the next request, so the provider can persist it
    # immediately.
    class Client
      PAGE_SIZE = 30
      MAX_PAGES = 20
      MAX_FIT_BYTES = 32 * 1024 * 1024
      MAX_PHOTO_BYTES = 20 * 1024 * 1024
      FIT_SIGNATURE = ".FIT"

      # One activity as the list describes it. `sport` is Zwift's own
      # `CYCLING`/`RUNNING`; `virtual_sport_slug` is what the provider
      # declares to the importer, while the FIT file keeps the last word on a
      # variant it names itself. `raw` is the listing item, kept for the
      # probe and for fields a later slice needs.
      Activity = Data.define(:id, :started_at, :name, :sport, :world_id, :distance_m,
                             :duration_s, :fit_bucket, :fit_key, :raw) do
        def initialize(id:, started_at: nil, name: nil, sport: nil, world_id: nil, distance_m: nil,
                       duration_s: nil, fit_bucket: nil, fit_key: nil, raw: nil)
          super
        end

        def virtual_sport_slug
          case sport.to_s.upcase
          when "CYCLING" then "cycling_virtual"
          when "RUNNING" then "running_virtual"
          end
        end
      end

      attr_reader :refresh_token, :expires_at

      def initialize(refresh_token:, access_token: nil, expires_at: nil, player_id: nil,
                     http: nil, on_tokens: nil)
        @refresh_token = refresh_token.to_s
        @access_token = access_token
        @expires_at = expires_at
        @player_id = player_id&.to_s
        @http = http || Http.new
        @auth = Auth.new(http: @http)
        @on_tokens = on_tokens
      end

      def profile
        body = get_json("/api/profiles/me")
        raise Error::Unavailable, "the profile is not an object" unless body.is_a?(Hash)

        body
      end

      # The summary fields the list omits (heart rate, cadence, speed, maximum
      # power, the FTP Zwift held at the time). The import reads the FIT
      # instead; this is the fallback when the list carries no FIT pointer.
      def activity(id)
        value = id.to_s
        raise ArgumentError, "not a Zwift activity id" unless value.match?(/\A[0-9A-Za-z_-]+\z/)

        get_json("/api/activities/#{value}")
      end

      # The photos Zwift attached to an activity (docs/dev/REMOTE-IMPORTS.md
      # §7d.3): the detail's `snapshotList`, keeping only the S3 objects the
      # download can safely fetch.
      def activity_photo_urls(id)
        body = activity(id)
        Array(body["snapshotList"]).filter_map { |url| url.to_s if photo_pointer(url) }
      end

      def player_id
        @player_id ||= begin
          id = profile["id"].to_s
          raise Error::Unavailable, "the profile carries no id" if id.empty?

          id
        end
        raise Error::Unavailable, "the profile id is not numeric" unless @player_id.match?(/\A\d+\z/)

        @player_id
      end

      def activities(start: 0, limit: PAGE_SIZE)
        data = get_json("/api/profiles/#{player_id}/activities",
                        params: { start: start.to_i, limit: limit.to_i })
        # The endpoint has returned both a bare list and an envelope over
        # time; accept either rather than depending on the current shape.
        rows = data.is_a?(Hash) ? (data["activities"] || data["data"] || []) : data
        Array(rows).map { |item| build_activity(item) }
      end

      # Every activity of `from..to` (dates), newest first. The listing is
      # newest-first with no date filter, so it walks pages until a page
      # reaches past `from`, ends short, or the cap is hit. Zwift exposes only
      # the newest 250 activities (§7d.1).
      def list(from:, to:, max_pages: MAX_PAGES)
        collected = []
        start = 0
        max_pages.times do
          page = activities(start:, limit: PAGE_SIZE)
          break if page.empty?

          collected.concat(page.select do |activity|
            activity.started_at && (from..to).cover?(activity.started_at.to_date)
          end)
          oldest = page.filter_map(&:started_at).min
          break if page.size < PAGE_SIZE || oldest.nil? || oldest.to_date < from

          start += PAGE_SIZE
        end
        collected
      end

      def download_fit(activity, io:)
        download_fit_object(bucket: activity.fit_bucket, key: activity.fit_key, io:)
      end

      def download_fit_object(bucket:, key:, io:)
        if bucket.to_s.empty? || key.to_s.empty?
          raise Error::NotFound, "the activity has no FIT file"
        end

        response = @http.download_s3(bucket:, key:, io:, max_bytes: MAX_FIT_BYTES)
        if response.status == 429
          raise Error::RateLimited.new(response.retry_after, "FIT download: HTTP 429")
        end
        raise Error::NotFound, "FIT download: HTTP 404" if response.status == 404
        raise Error::Unavailable, "FIT download: HTTP #{response.status}" unless response.success?

        io.rewind
        header = io.read(12).to_s
        io.rewind
        raise Error::Unavailable, "the download is not a FIT file" unless header.byteslice(8, 4) == FIT_SIGNATURE

        io
      end

      # Downloads one of an activity's snapshots into `io`. The URL is split
      # into its bucket and key and both are validated like the FIT's, so a
      # hostile answer can never redirect the request.
      def download_photo(url, io:)
        bucket, key = photo_pointer(url)
        raise Error::NotFound, "the photo is not a Zwift S3 object" if bucket.nil?

        response = @http.download_s3(bucket:, key:, io:, max_bytes: MAX_PHOTO_BYTES)
        raise Error::NotFound, "photo download: HTTP 404" if response.status == 404
        raise Error::Unavailable, "photo download: HTTP #{response.status}" unless response.success?

        io.rewind
        io
      end

      private

      # A snapshot URL as [bucket, key], or nil when it is not one of Zwift's
      # S3 objects.
      def photo_pointer(url)
        uri = URI(url.to_s)
        return nil unless uri.is_a?(URI::HTTPS)

        host = uri.host.to_s.downcase
        return nil unless host.end_with?(Http::S3_SUFFIX)

        bucket = host.delete_suffix(Http::S3_SUFFIX)
        key = uri.path.to_s.delete_prefix("/")
        return nil unless @http.safe_s3_object?(bucket, key)

        [ bucket, key ]
      rescue URI::InvalidURIError
        nil
      end

      def get_json(path, params: nil)
        ensure_access_token
        response = @http.get(path, params:, headers: auth_headers)
        if response.status == 401
          refresh!
          response = @http.get(path, params:, headers: auth_headers)
        end
        check(response, path)
        body = response.json
        raise Error::Unavailable, "#{path}: the answer is not JSON" if body.nil?

        body
      end

      def auth_headers
        { "Authorization" => "Bearer #{@access_token}", "Accept" => "application/json" }
      end

      def ensure_access_token
        return if @access_token && @expires_at && @expires_at > Time.now + 60

        refresh!
      end

      def refresh!
        tokens = @auth.refresh(refresh_token: @refresh_token)
        @access_token = tokens.access_token
        @refresh_token = tokens.refresh_token if tokens.refresh_token && !tokens.refresh_token.empty?
        @expires_at = tokens.expires_at
        @on_tokens&.call(tokens)
      end

      def check(response, path)
        case response.status
        when 200..299 then nil
        when 401 then raise Error::SignedOut, "#{path}: the access token was refused after a refresh"
        when 404 then raise Error::NotFound, "#{path}: HTTP 404"
        when 429 then raise Error::RateLimited.new(response.retry_after, "#{path}: HTTP 429")
        else raise Error::Unavailable, "#{path}: HTTP #{response.status}"
        end
      end

      def build_activity(item)
        Activity.new(
          id: (item["id"] || item["id_str"] || item["activityId"])&.to_s,
          started_at: parse_time(item["startDate"]),
          name: item["name"] || item["activityName"],
          sport: item["sport"],
          world_id: item["worldId"]&.to_i,
          distance_m: item["distanceInMeters"]&.to_f,
          duration_s: duration_seconds(item),
          fit_bucket: item["fitFileBucket"],
          fit_key: item["fitFileKey"],
          raw: item
        )
      end

      def duration_seconds(item)
        return item["durationInSeconds"].to_f if item["durationInSeconds"]

        item["duration"] && item["duration"].to_f * 60
      end

      # Zwift's `startDate` is UTC. A value that carries no zone is read as
      # UTC rather than as the server's local time.
      def parse_time(value)
        text = value.to_s.strip
        return nil if text.empty?

        text += "Z" unless text.match?(/(?:Z|[+-]\d{2}:?\d{2})\z/i)
        Time.iso8601(text).utc
      rescue ArgumentError
        begin
          Time.parse(text).utc
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
