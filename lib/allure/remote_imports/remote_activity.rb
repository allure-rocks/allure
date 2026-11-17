# frozen_string_literal: true

require "time"

module Allure
  module RemoteImports
    # One activity as a provider's listing describes it, before any fetch
    # (docs/dev/REMOTE-IMPORTS.md). `geometry` describes what the listing
    # declares: an indoor activity without a GPS track is imported as a
    # positionless recording (docs/dev/NO-GPS.md), never skipped for that
    # reason; `manual` marks an activity whose provider holds no file at all,
    # which is skipped without a request; `ended_at` carries the listed end,
    # either the window a fetch needs (Withings's series) or the end a listing
    # declares before its activity is settled (Zwift's in-progress rule).
    # `provider_metadata` is a provider-specific hash that round trips through
    # the entry, for what the fetch needs and the listing alone knows (Zwift's
    # `fit_bucket`/`fit_key`, §7d.3); it is empty for the others. The value
    # round trips through an import entry's metadata.
    RemoteActivity = Data.define(:external_id, :name, :started_at, :ended_at, :sport_hint, :geometry, :manual,
                                 :provider_metadata) do
      def initialize(external_id:, name: nil, started_at: nil, ended_at: nil, sport_hint: nil, geometry: true,
                     manual: false, provider_metadata: {})
        super
      end

      def self.from_metadata(external_id, metadata)
        metadata = metadata.to_h.transform_keys(&:to_s)
        started_at = metadata["started_at"].to_s
        ended_at = metadata["ended_at"].to_s
        provider_metadata = metadata["provider_metadata"]
        new(
          external_id: external_id.to_s,
          name: metadata["name"],
          started_at: started_at.empty? ? nil : Time.iso8601(started_at),
          ended_at: ended_at.empty? ? nil : Time.iso8601(ended_at),
          sport_hint: metadata["sport_hint"],
          geometry: metadata.fetch("geometry", true) != false,
          manual: metadata.fetch("manual", false) == true,
          provider_metadata: provider_metadata.is_a?(Hash) ? provider_metadata : {}
        )
      end

      def metadata
        values = {
          "name" => name,
          "started_at" => started_at&.utc&.iso8601,
          "ended_at" => ended_at&.utc&.iso8601,
          "sport_hint" => sport_hint,
          "geometry" => geometry,
          "manual" => manual
        }.compact
        values["provider_metadata"] = provider_metadata.to_h unless provider_metadata.to_h.empty?
        values
      end
    end
  end
end
