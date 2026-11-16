# frozen_string_literal: true

require "tempfile"

module ImportConnections
  module Providers
    # The Zwift adapter (docs/dev/REMOTE-IMPORTS.md) over the pure
    # `Allure::Zwift::Client`. The only credential is the refresh token, which
    # rotates on every refresh and is written back at once; the FIT file names
    # its platform and its virtual sport, so neither equipment nor a fallback
    # sport exists. The listing carries the S3 pointer, kept in the entry's
    # provider metadata so the fetch needs no extra API call.
    class Zwift
      RATE_LIMIT_PAUSE = 15.minutes
      TITLE_LENGTH = 255
      # Zwift lists the activity the athlete is still riding: it exists from the
      # start, under a provisional name, with a FIT file its uploader is still
      # writing. Importing it would freeze a truncated recording under an
      # external id no later sync re-imports (the listing is deduplicated by
      # external id), so an activity is listed only once its declared end has
      # settled.
      SETTLE = 10.minutes

      def initialize(connection)
        @connection = connection
      end

      def list(from:, to:)
        rows = call { client.list(from: from.utc.to_date, to: to.utc.to_date) }
        now = Time.current
        rows.filter_map do |row|
          next if row.id.blank?

          ended_at = declared_end(row)
          next if unsettled?(row, ended_at, now)

          Allure::RemoteImports::RemoteActivity.new(
            external_id: row.id,
            name: row.name&.truncate(TITLE_LENGTH),
            started_at: row.started_at,
            ended_at:,
            sport_hint: row.virtual_sport_slug,
            geometry: true,
            manual: false,
            provider_metadata: { "fit_bucket" => row.fit_bucket, "fit_key" => row.fit_key }.compact
          )
        end
      end

      def fetch(activity)
        bucket, key = fit_pointer(activity)
        file = Tempfile.new([ "zwift-#{activity.external_id}", ".fit" ], binmode: true)
        call { client.download_fit_object(bucket:, key:, io: file) }
        Allure::RemoteImports::FetchedActivity.new(
          io: file, filename: "zwift-#{activity.external_id}.fit",
          title: activity.name.presence, declared_sport: activity.sport_hint
        )
      rescue ArgumentError => error
        file&.close!
        raise Allure::RemoteImports::Error::NotFound, error.message
      rescue StandardError
        file&.close!
        raise
      end

      def equipment = []

      # The photos Zwift attached to the activity (docs/dev/REMOTE-IMPORTS.md
      # §7d.3): the activity detail lists them, and each is a public S3 object
      # like the FIT. A photo that cannot be downloaded is counted as missing,
      # never fatal — the import itself has already succeeded.
      def photos(activity)
        return Allure::RemoteImports::PhotoSet.new unless Allure::Photos::Config.enabled?

        urls = call { client.activity_photo_urls(activity.external_id) }
        photos = urls.each_with_index.filter_map { |url, index| download_photo(activity, url, index) }
        Allure::RemoteImports::PhotoSet.new(listed: urls.length, photos:)
      rescue Allure::RemoteImports::Error
        Allure::RemoteImports::PhotoSet.new
      end

      # Best effort: the Keycloak logout revokes the refresh token, and a
      # failure never blocks the unlink.
      def deauthorize!
        Allure::Zwift::Auth.new.logout(refresh_token: @connection.credential(:refresh_token))
      rescue StandardError
        nil
      end

      # One authenticated profile call proves the refresh token opens the
      # account.
      def verify!
        call { client.profile }
        true
      end

      private

      # The end the listing declares, when it declares a duration.
      def declared_end(row)
        return nil if row.started_at.nil? || row.duration_s.nil?

        row.started_at + row.duration_s
      end

      # An activity Zwift has not finished writing yet: it started inside the
      # settle window, or its declared end has not passed it. Its name is still
      # provisional and its FIT is a snapshot, so it waits for a later sync. A
      # row with no duration is settled once it started long enough ago.
      def unsettled?(row, ended_at, now)
        return false if row.started_at.nil?

        horizon = now - SETTLE
        return true if row.started_at > horizon

        ended_at.present? && ended_at > horizon
      end

      # One snapshot, downloaded into a tempfile the caller closes. A photo the
      # download refuses is skipped: the activity's photos are a bonus, never a
      # reason to fail the import.
      def download_photo(activity, url, index)
        file = Tempfile.new([ "zwift-#{activity.external_id}-#{index}", ".jpg" ], binmode: true)
        call { client.download_photo(url, io: file) }
        Allure::RemoteImports::Photo.new(io: file, filename: "zwift-#{activity.external_id}-#{index}.jpg")
      rescue StandardError
        file&.close!
        nil
      end

      def client
        @client ||= Allure::Zwift::Client.new(
          refresh_token: refresh_token,
          player_id: @connection.credential(:player_id),
          on_tokens: method(:persist_tokens)
        )
      end

      def refresh_token
        token = @connection.credential(:refresh_token)
        raise Allure::RemoteImports::Error::AuthError, "no Zwift refresh token" if token.blank?

        token
      end

      def persist_tokens(tokens)
        current = @connection.credentials.to_h
        @connection.update!(
          credentials: current.merge("refresh_token" => tokens.refresh_token.presence || current["refresh_token"]),
          token_expires_at: tokens.refresh_expires_at || tokens.expires_at || @connection.token_expires_at
        )
      end

      def fit_pointer(activity)
        metadata = activity.provider_metadata.to_h.transform_keys(&:to_s)
        bucket = metadata["fit_bucket"]
        key = metadata["fit_key"]
        raise Allure::RemoteImports::Error::NotFound, "the listing carries no FIT pointer" if bucket.blank? || key.blank?

        [ bucket, key ]
      end

      def call
        yield
      rescue Allure::Zwift::Error::RefreshRejected, Allure::Zwift::Error::SignedOut,
             Allure::Zwift::Error::InvalidCredentials => error
        raise Allure::RemoteImports::Error::AuthError, error.message
      rescue Allure::Zwift::Error::RateLimited => error
        raise Allure::RemoteImports::Error::RateLimited.new(error.message, retry_at: RATE_LIMIT_PAUSE.from_now)
      rescue Allure::Zwift::Error::NotFound => error
        raise Allure::RemoteImports::Error::NotFound, error.message
      rescue Allure::Zwift::Error => error
        raise Allure::RemoteImports::Error::Unavailable, error.message
      end
    end
  end
end
