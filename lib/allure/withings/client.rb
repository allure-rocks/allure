# frozen_string_literal: true

require "time"

module Allure
  module Withings
    # Reads a signed-in Withings account (PLAN_REMOTE_IMPORTS.md §7c.3): the
    # workout list, window by window, and the two per-second series of one
    # session — locations and heart-rate samples. Only POSTs are sent; the
    # session id and userid travel in every form.
    class Client
      ACTIVITY_PATH = "/cgi-bin/v2/activity"
      MEASURE_PATH = "/cgi-bin/v2/measure"
      # The platform key is `apppfm` on the v2 endpoints (§7c.1).
      APP_FORM = { "appname" => "wiscaleNG", "apppfm" => "ios", "appliver" => 4050301 }.freeze
      WINDOW_DAYS = 30
      MAX_WINDOWS = 50
      LOCATION_MEASTYPES = "98,99,97,72,96,101,100"
      HEART_RATE_MEASTYPES = "11,43,73,89"
      # Withings's auto-detected step sessions (category 128): recorded
      # without a workout, they are skipped before any fetch.
      NO_ACTIVITY_CATEGORY = 128
      # The data keys that mark a sleep summary in the listing (observed
      # 2026-11-01): health data, decision 7 excludes them.
      SLEEP_DATA_KEYS = %w[wakeupduration lightsleepduration deepsleepduration
                           remsleepduration night_events].freeze

      # One workout as the listing describes it. `gps` is the summary hash
      # or nil; `data` the aggregates hash or nil; `ended_at` nil on an
      # entry without an end; `raw` the listing item itself, kept for the
      # probe and the device names of a later slice (the items carry
      # `model` and `brand`). The workout-category enum arrives as
      # `subcategory` (§7c.1).
      Activity = Data.define(:id, :started_at, :ended_at, :category, :gps, :data, :raw) do
        def initialize(id:, started_at:, ended_at: nil, category: nil, gps: nil, data: nil, raw: nil)
          super
        end

        def positioned? = !gps.nil?

        def auto_detected? = category == NO_ACTIVITY_CATEGORY

        # A sleep summary rides the same listing (observed 2026-11-01):
        # decision 7 excludes sleep, so the provider skips these by shape.
        def sleep? = (data&.keys || []).intersect?(SLEEP_DATA_KEYS)
      end

      # One `getvasistas` answer: `dates` the epochs, `rows` the value rows
      # (a location row's first two values are latitude and longitude; a
      # heart-rate row's first value is the bpm).
      Series = Data.define(:dates, :rows) do
        def self.empty = new(dates: [], rows: [])
      end

      attr_reader :session_id, :user_id

      def initialize(session_id:, user_id:, http: nil)
        @session_id = session_id.to_s
        @user_id = user_id
        @http = http || Http.new
      end

      # Every workout of `from..to` (dates), newest first. The listing walks
      # the range in 30-day windows — the paging the reference drives —
      # bounded to `MAX_WINDOWS`.
      def activities(from:, to:, max_windows: MAX_WINDOWS)
        window_to = to
        collected = []
        max_windows.times do
          break if window_to < from

          window_from = [ from, window_to - WINDOW_DAYS ].max
          collected.concat(activities_in_window(from: window_from, to: window_to))
          break if window_from == from

          window_to = window_from - 1
        end
        collected.sort_by { |item| -item.started_at.to_i }
      end

      # One `getbyuserid` call over the window, as raw hashes — the probe's
      # wide-window check and the provider's listing share it.
      def activities_in_window(from:, to:)
        body = post(ACTIVITY_PATH, {
          "action" => "getbyuserid",
          "userid" => @user_id,
          "startdateymd" => from.iso8601,
          "enddateymd" => to.iso8601,
          "callctx" => "foreground",
          "sessionid" => @session_id
        }.merge(APP_FORM))
        Array(body.dig("body", "series")).map { |item| build_activity(item) }
      end
      # The location samples of a session (may be empty).
      def location_series(started_at, ended_at)
        vasistas(started_at, ended_at, meastypes: LOCATION_MEASTYPES, category: "location")
      end

      # The heart-rate samples of a session (may be empty).
      def heart_rate_series(started_at, ended_at)
        vasistas(started_at, ended_at, meastypes: HEART_RATE_MEASTYPES, category: "hr")
      end

      # The official API's high-frequency companion (`getintradayactivity`),
      # which the private endpoint serves too: the probe uses it to discover
      # where this watch's location track lives when `getvasistas` answers a
      # single sample (§7c.1). Returns the parsed envelope.
      def intraday_activity(started_at, ended_at)
        post(MEASURE_PATH, {
          "action" => "getintradayactivity",
          "userid" => @user_id,
          "startdate" => started_at.to_i,
          "enddate" => ended_at.to_i,
          "sessionid" => @session_id
        }.merge(APP_FORM))
      end

      private

      def vasistas(started_at, ended_at, meastypes:, category:)
        body = post(MEASURE_PATH, {
          "action" => "getvasistas",
          "userid" => @user_id,
          "startdate" => started_at.to_i,
          "enddate" => ended_at.to_i,
          "callctx" => "foreground",
          "meastype" => meastypes,
          "vasistas_category" => category,
          "sessionid" => @session_id
        }.merge(APP_FORM))
        series = body.dig("body", "series", 0) || {}
        Series.new(dates: Array(series["dates"]), rows: Array(series["vasistas"]))
      end

      def build_activity(item)
        Activity.new(
          id: item["id"],
          started_at: epoch_time(item["startdate"]),
          ended_at: epoch_time(item["enddate"]),
          # The private listing names the public API's workout category
          # `subcategory` (observed 2026-11-01: `subcategory: 187`, rowing);
          # `category` stays as a fallback for an answer shape that uses it.
          category: (item["subcategory"] || item["category"])&.to_i,
          gps: item["gps"].is_a?(Hash) ? item["gps"] : nil,
          data: item["data"].is_a?(Hash) ? item["data"] : nil,
          raw: item
        )
      end

      def epoch_time(value)
        value.nil? ? nil : Time.at(value.to_i).utc
      end

      def post(path, form)
        response = @http.post_form(path, form:)
        raise Error::RateLimited, "#{path}: HTTP 429" if response.status == 429
        raise Error::Unavailable, "#{path}: HTTP #{response.status}" unless response.success?

        body = response.json
        raise Error::Unavailable, "#{path}: the answer is not JSON" if body.nil?

        status = body["status"].to_i
        raise Error::ApiStatus.new(status, body["error"]) unless status.zero?

        body
      end
    end
  end
end
