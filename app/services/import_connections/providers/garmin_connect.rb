# frozen_string_literal: true

require "tempfile"
require "time"

module ImportConnections
  module Providers
    # The Garmin Connect adapter (docs/dev/REMOTE-IMPORTS.md) over the pure
    # `Allure::GarminConnect::Client`. The DI token lives in the connection's
    # credentials; a rotated token is written back the moment the client
    # refreshes it, because the previous refresh token is spent.
    class GarminConnect
      PAGE_SIZE = Allure::GarminConnect::Client::ACTIVITY_PAGE_SIZE
      MAX_PAGES = 50
      MAX_EQUIPMENT = 100
      RATE_LIMIT_PAUSE = 15.minutes
      GC = Allure::GarminConnect

      def initialize(connection)
        @connection = connection
      end

      def list(from:, to:)
        window = from..to
        activities = []
        MAX_PAGES.times do |page|
          items = Array(call { client.activities(start: page * PAGE_SIZE, limit: PAGE_SIZE,
                                                 start_date: from.to_date, end_date: to.to_date) })
          activities.concat(items.filter_map { |item| remote_activity(item) })
          break if items.length < PAGE_SIZE
        end
        activities.select { |activity| activity.started_at.nil? || window.cover?(activity.started_at) }
      end

      def fetch(activity)
        archive = Tempfile.new([ "garmin-#{activity.external_id}", ".zip" ], binmode: true)
        call { client.download_original(activity.external_id, io: archive) }
        original, filename = extract_original(archive, activity.external_id)

        Allure::RemoteImports::FetchedActivity.new(
          io: original,
          filename:,
          title: activity.name.presence,
          equipment_external_id: (activity_gear_id(activity.external_id) if @connection.sync_equipment),
          metadata: { "garmin_type" => activity.sport_hint }.compact
        )
      ensure
        archive&.close!
      end

      # Garmin Connect photos are not imported yet (PLAN_PHOTOS.md §6).
      def photos(_activity) = Allure::RemoteImports::PhotoSet.new

      def equipment
        return [] if @connection.external_account_id.blank?

        Array(call { client.gear(@connection.external_account_id) }).first(MAX_EQUIPMENT).filter_map do |item|
          next unless item.is_a?(Hash) && item["uuid"].present?

          Allure::RemoteImports::RemoteEquipment.new(
            external_id: item["uuid"].to_s,
            name: (item["displayName"].presence || item["customMakeModel"].presence || item["gearModelName"]).to_s,
            kind: item["gearTypeName"].to_s.casecmp?("bike") ? "bike" : "shoes",
            brand: item["gearMakeName"].presence,
            model: item["gearModelName"].presence,
            active: item["gearStatusName"].to_s.casecmp?("active")
          )
        end
      end

      # Garmin has no revocation endpoint: unlinking wipes the tokens.
      def deauthorize!
        nil
      end

      # The gear recorded on one activity, for equipment attached after import.
      def equipment_external_id_for(external_id)
        activity_gear_id(external_id)
      end

      # The social profile, which proves the token and names the account.
      def profile
        call { client.social_profile }
      end

      private

      def remote_activity(item)
        return nil unless item.is_a?(Hash) && item["activityId"].present?

        Allure::RemoteImports::RemoteActivity.new(
          external_id: item["activityId"].to_s,
          name: item["activityName"].presence,
          started_at: parse_gmt(item["startTimeGMT"]),
          sport_hint: item.dig("activityType", "typeKey").presence,
          # A manual activity carries no file to fetch; an indoor one is
          # fetched and imported positionlessly (PLAN_NO_GPS.md §8).
          geometry: item["hasPolyline"] == true,
          manual: item["manualActivity"] == true
        )
      end

      # "2026-08-30 11:35:18", in UTC.
      def parse_gmt(value)
        return nil if value.blank?

        Time.find_zone("UTC").parse(value.to_s)
      rescue ArgumentError
        nil
      end

      # The download is a ZIP holding `<id>_ACTIVITY.fit` (older activities may
      # hold a GPX or TCX); the first track entry is the original.
      def extract_original(archive, external_id)
        archive.rewind
        return raw_original(archive, external_id) unless archive.read(2) == "PK"

        archive.rewind
        reader = Workouts::ArchiveReader.new
        reader.each_entry(archive, filename: "#{external_id}.zip") do |entry|
          extension = File.extname(entry.name).downcase
          copy = Tempfile.new([ "garmin-#{external_id}", extension ], binmode: true)
          IO.copy_stream(entry.io, copy)
          copy.rewind
          return [ copy, "garmin-#{external_id}#{extension}" ]
        end
        raise Allure::RemoteImports::Error::NotFound, "no track file in the Garmin download"
      rescue Workouts::ArchiveReader::Error => error
        raise Allure::RemoteImports::Error::Unavailable, "unreadable Garmin download: #{error.message}"
      end

      # A download that is not a ZIP is the FIT itself.
      def raw_original(archive, external_id)
        archive.rewind
        copy = Tempfile.new([ "garmin-#{external_id}", ".fit" ], binmode: true)
        IO.copy_stream(archive, copy)
        copy.rewind
        [ copy, "garmin-#{external_id}.fit" ]
      end

      def activity_gear_id(external_id)
        items = Array(call { client.activity_gear(external_id) })
        items.find { |item| item.is_a?(Hash) && item["uuid"].present? }&.fetch("uuid")&.to_s
      rescue Allure::RemoteImports::Error::NotFound
        nil
      end

      def client
        @client ||= GC::Client.new(token:, region: GC::Region.new(@connection.region), on_refresh: method(:persist_token))
      end

      def token
        credentials = @connection.credentials.to_h
        raise Allure::RemoteImports::Error::AuthError, "no Garmin token" if credentials["di_token"].blank?

        GC::DiToken::Token.new(
          access_token: credentials["di_token"],
          refresh_token: credentials["di_refresh_token"],
          client_id: credentials["di_client_id"],
          expires_at: @connection.token_expires_at
        )
      end

      def persist_token(token)
        @connection.update!(
          credentials: @connection.credentials.to_h.merge(
            "di_token" => token.access_token,
            "di_refresh_token" => token.refresh_token,
            "di_client_id" => token.client_id
          ),
          token_expires_at: token.expires_at
        )
      end

      def call
        yield
      rescue GC::Error::TokenRejected, GC::Error::InvalidCredentials, GC::Error::MfaFailed => error
        raise Allure::RemoteImports::Error::AuthError, error.message
      rescue GC::Error::RateLimited => error
        raise Allure::RemoteImports::Error::RateLimited.new(error.message, retry_at: RATE_LIMIT_PAUSE.from_now)
      rescue GC::Error::NotFound => error
        raise Allure::RemoteImports::Error::NotFound, error.message
      rescue GC::Error::Refused => error
        raise Allure::RemoteImports::Error::Refused, error.message
      rescue GC::Error::Unavailable => error
        raise Allure::RemoteImports::Error::Unavailable, error.message
      end
    end
  end
end
