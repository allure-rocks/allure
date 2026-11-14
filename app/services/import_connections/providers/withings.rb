# frozen_string_literal: true

require "tempfile"

module ImportConnections
  module Providers
    # The Withings adapter (PLAN_REMOTE_IMPORTS.md §7c.3) over the pure
    # `Allure::Withings::Client`. The only credentials are the private API's
    # session id and the userid; the synthesized TCX original carries the
    # positions, the elevation, the heart rate and the sport's TCX name, and
    # the listing's `subcategory` names the declared sport. Sleep summaries
    # and entries with nothing to record are skipped before any fetch
    # (decision 7, decision 9).
    class Withings
      def initialize(connection)
        @connection = connection
      end

      # The listing walks 30-day windows inside the range (§7c.3) and drops
      # the entries decision 7 and the provider contract skip: sleep
      # summaries, entries without an end, and summaries without a heart-rate
      # aggregate or positions (nothing to record).
      def list(from:, to:)
        call { client.activities(from: from.utc.to_date, to: to.utc.to_date) }.filter_map do |activity|
          next if skippable?(activity)

          Allure::RemoteImports::RemoteActivity.new(
            external_id: activity.id.to_s,
            name: nil,
            started_at: activity.started_at,
            ended_at: activity.ended_at,
            sport_hint: activity.category,
            geometry: activity.positioned?,
            manual: false
          )
        end
      end

      def fetch(activity)
        started_at = activity.started_at || raise(Allure::RemoteImports::Error::NotFound, "no listed start")
        ended_at = activity.ended_at || started_at + 1.second

        location = call { client.location_series(started_at, ended_at) }
        heart_rate = call { client.heart_rate_series(started_at, ended_at) }
        # A session announced with a route but answered with fewer than two
        # positions carries no track (observed 2026-11-01: one sample); with
        # the connection importing positioned sessions only, that is no
        # geometry, not a heart-rate fallback.
        if @connection.positioned_only? && location.rows.size < 2
          raise Allure::RemoteImports::Error::NoGeometry, "fewer than two location samples"
        end
        listed = call { client.activities_in_window(from: started_at.to_date, to: started_at.to_date) }
                 .find { |item| item.id.to_s == activity.external_id }
        file = Tempfile.new([ "withings-#{activity.external_id}", ".tcx" ], binmode: true)
        file.write(
          Allure::Withings::TcxWriter.build(
            activity: listed || Allure::Withings::Client::Activity.new(
              id: activity.external_id, started_at:, ended_at:
            ),
            location:, heart_rate:
          )
        )
        file.rewind
        Allure::RemoteImports::FetchedActivity.new(
          io: file, filename: "withings-#{activity.external_id}.tcx",
          declared_sport: Allure::Withings::SportMapping.slug(listed&.category || activity.sport_hint.to_i)
        )
      rescue Allure::Withings::Error::NoSamples
        file&.close!
        raise Allure::RemoteImports::Error::NotFound,
              "the session recorded neither a position nor a heart-rate sample"
      rescue StandardError
        file&.close!
        raise
      end

      def equipment = []

      # A Withings session carries no photo.
      def photos(_activity) = Allure::RemoteImports::PhotoSet.new

      # Withings offers no revocation: unlinking forgets the session.
      def deauthorize!
        nil
      end

      # One authenticated listing proves the session still opens the account.
      def verify!
        call { client.activities_in_window(from: Time.current.to_date, to: Time.current.to_date) }
        true
      end

      private

      def client
        @client ||= Allure::Withings::Client.new(session_id:, user_id:)
      end

      def session_id
        credentials = @connection.credentials.to_h
        raise Allure::RemoteImports::Error::AuthError, "no Withings session" if credentials["sessionid"].blank?

        credentials["sessionid"]
      end

      def user_id
        credentials = @connection.credentials.to_h
        raise Allure::RemoteImports::Error::AuthError, "no Withings userid" if credentials["userid"].blank?

        credentials["userid"]
      end

      def skippable?(activity)
        activity.sleep? || activity.ended_at.nil? ||
          (!activity.positioned? && !activity.data&.key?("hr_average"))
      end

      def call
        yield
      rescue Allure::Withings::Error::ApiStatus => error
        if NATURAL_SESSION_STATUSES.include?(error.status)
          raise Allure::RemoteImports::Error::SessionEnded, error.message
        end
        raise Allure::RemoteImports::Error::AuthError, error.message
      rescue Allure::Withings::Error::RateLimited => error
        raise Allure::RemoteImports::Error::RateLimited.new(error.message, retry_at: 15.minutes.from_now)
      rescue Allure::Withings::Error => error
        raise Allure::RemoteImports::Error::Unavailable, error.message
      end

      # 250 (corrupted credentials) and 501 (the session's natural end) both
      # mean the connection must be made again (observed 2026-11-01, §7c.1).
      NATURAL_SESSION_STATUSES = [ 250, 501 ].freeze
    end
  end
end
