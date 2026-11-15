# frozen_string_literal: true

module Allure
  module Virtual
    # One detectable virtual-activity system (docs/dev/VIRTUAL-PLATFORMS.md). A platform is
    # pure catalogue data: the rest of the application never names a provider,
    # it resolves one from the file and asks this object for what to do.
    #
    # - `fit_fingerprints` are partial `file_id` hashes; an entry matches when
    #   every declared field equals the file's value, so a provider can be
    #   pinned by manufacturer alone or by the full triple it writes;
    # - `creator_aliases` match the creator string of any format (FIT
    #   product_name, GPX `<gpx creator>`), normalised to snake_case tokens;
    # - `sport_slug` is the fallback sport used only when the file itself
    #   carries no usable sport, so a provider whose FIT sport is ambiguous
    #   still lands on its real sport;
    # - `venues` name the virtual worlds and recognise them from the start
    #   point; a provider without venues (a pure ergometer) simply has none.
    Platform = Data.define(:key, :name, :fit_fingerprints, :creator_aliases, :sport_slug, :venues) do
      def initialize(key:, name:, fit_fingerprints: [], creator_aliases: [], sport_slug: nil, venues: [])
        super(
          key: key.to_s.freeze,
          name: name.to_s.freeze,
          fit_fingerprints: fit_fingerprints.map { |fingerprint| fingerprint.to_h.freeze }.freeze,
          creator_aliases: creator_aliases.map { |creator_alias| Platforms.normalize(creator_alias).freeze }.freeze,
          sport_slug: sport_slug&.to_s,
          venues: venues.map { |venue| Venue.new(**venue) }.freeze
        )
      end

      def matches_creator?(creator)
        normalized = Platforms.normalize(creator)
        return false if normalized.empty?

        creator_aliases.any? do |creator_alias|
          next false if creator_alias.empty?

          normalized == creator_alias ||
            normalized.match?(/(?:\A|_)#{Regexp.escape(creator_alias)}(?:\z|_)/)
        end
      end

      def matches_file_id?(file_id)
        fields = file_id.to_h
        fit_fingerprints.any? do |fingerprint|
          fingerprint.all? { |field, expected| fields[field] == expected }
        end
      end

      # The venue whose radius contains the point; the closest one wins when
      # two worlds overlap. Nil when the point belongs to no known world.
      def venue_at(longitude:, latitude:)
        venues
          .map { |venue| [ venue, venue.distance_to(longitude:, latitude:) ] }
          .select { |venue, distance| distance <= venue.radius_m }
          .min_by { |_venue, distance| distance }
          &.first
      end
    end
  end
end
