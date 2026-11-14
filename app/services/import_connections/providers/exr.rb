# frozen_string_literal: true

require "tempfile"

module ImportConnections
  module Providers
    # The EXR adapter (PLAN_REMOTE_IMPORTS.md §7b.3) over the pure
    # `Allure::Exr::Client`. The only credential is the account site's
    # remember cookie; a cookie the site replaces is written back at once.
    # The FIT file names its platform, so neither a sport hint nor equipment
    # exists.
    class Exr
      RATE_LIMIT_PAUSE = 15.minutes
      TITLE_LENGTH = 255

      def initialize(connection)
        @connection = connection
      end

      # The listed start is UTC (§7b.5); rows are kept inside the window.
      def list(from:, to:)
        window = from..to
        rows = call { client.list(from: from.utc.to_date, to: to.utc.to_date) }
        rows.filter_map do |row|
          next unless row.listed_at.nil? || window.cover?(row.listed_at)

          Allure::RemoteImports::RemoteActivity.new(
            external_id: row.uuid, name: row.title&.truncate(TITLE_LENGTH), started_at: row.listed_at,
            sport_hint: nil, geometry: true, manual: false
          )
        end
      end

      def fetch(activity)
        file = Tempfile.new([ "exr-#{activity.external_id}", ".fit" ], binmode: true)
        call { client.download_fit(activity.external_id, io: file) }
        Allure::RemoteImports::FetchedActivity.new(io: file, filename: "exr-#{activity.external_id}.fit",
                                                   title: activity.name.presence)
      rescue StandardError
        file&.close!
        raise
      end

      def equipment = []

      # EXR attaches no photo to a session.
      def photos(_activity) = Allure::RemoteImports::PhotoSet.new

      # EXR offers no revocation: unlinking forgets the cookie.
      def deauthorize!
        nil
      end

      # The first page, which proves the cookie opens the account.
      def verify!
        call { client.page(1) }
        true
      end

      private

      def client
        @client ||= Allure::Exr::Client.new(remember:, on_rotate: method(:persist_cookie))
      end

      def remember
        credentials = @connection.credentials.to_h
        raise Allure::RemoteImports::Error::AuthError, "no EXR cookie" if credentials["remember_cookie"].blank?

        Allure::Exr::Http::Cookie.new(name: credentials["remember_cookie_name"], value: credentials["remember_cookie"],
                                      expires_at: @connection.token_expires_at)
      end

      def persist_cookie(cookie)
        @connection.update!(
          credentials: @connection.credentials.to_h.merge("remember_cookie_name" => cookie.name,
                                                          "remember_cookie" => cookie.value),
          token_expires_at: cookie.expires_at || @connection.token_expires_at
        )
      end

      def call
        yield
      rescue Allure::Exr::Error::SignedOut, Allure::Exr::Error::InvalidCredentials => error
        raise Allure::RemoteImports::Error::AuthError, error.message
      rescue Allure::Exr::Error::RateLimited => error
        raise Allure::RemoteImports::Error::RateLimited.new(error.message, retry_at: RATE_LIMIT_PAUSE.from_now)
      rescue Allure::Exr::Error::NotFound => error
        raise Allure::RemoteImports::Error::NotFound, error.message
      rescue Allure::Exr::Error => error
        raise Allure::RemoteImports::Error::Unavailable, error.message
      end
    end
  end
end
