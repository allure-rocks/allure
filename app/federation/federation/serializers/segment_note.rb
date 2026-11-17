# frozen_string_literal: true

module Federation
  module Serializers
    # The course Note (docs/dev/SEGMENTS-FEDERATION.md). It carries geometry,
    # name, description, sport, and course metrics only: an effort, athlete,
    # alias, leaderboard row, or activity timestamp never appears here.
    class SegmentNote
      ACTIVITY_STREAMS_CONTEXT = "https://www.w3.org/ns/activitystreams"
      PUBLIC_AUDIENCE = "#{ACTIVITY_STREAMS_CONTEXT}#Public"
      # Wire tag name => representation key. `elevation_gain`/`elevation_loss`
      # keep the legacy workout dialect.
      METRIC_TAGS = {
        "distance" => "distance",
        "elevation_gain" => "ascent",
        "elevation_loss" => "descent",
        "average_grade" => "average_grade",
        "match_tolerance" => "match_tolerance"
      }.freeze
      METRE_TAGS = %w[distance elevation_gain elevation_loss match_tolerance].freeze

      class Unavailable < StandardError; end

      def initialize(publication:, actor: nil, actor_uri: nil, config: Allure::Federation.config)
        @publication = publication
        @representation = publication.representation.stringify_keys
        @actor_uri = actor&.uri || actor_uri || publication.actor.uri
        @config = config
      end

      def call
        raise Unavailable, "publication is not active" unless @publication.active?
        raise Unavailable, "publication has no sanitized course" unless @publication.sanitized_attachment(:gpx)

        note = {
          "@context" => ACTIVITY_STREAMS_CONTEXT,
          "id" => @publication.object_uri,
          "type" => "Note",
          "attributedTo" => @actor_uri,
          "name" => name,
          "content" => content,
          "url" => local_url,
          "published" => published_at,
          "to" => audience.fetch("to"),
          "cc" => audience.fetch("cc"),
          "tag" => tags
        }
        note["location"] = location if location
        note["attachment"] = attachments if attachments.any?
        note
      end

      private

      def name
        value = @representation["name"]
        raise Unavailable, "publication name is invalid" unless value.is_a?(String) && value.present?

        value
      end

      def published_at
        @publication.published_at.utc.iso8601
      end

      def content
        values = [ @representation["name"], @representation["description"] ]
          .filter_map { |value| value.to_s.presence }
        values = [ name ] if values.empty?
        values.map { |value| ERB::Util.html_escape(value) }.join("<br>")
      end

      # Informational only: a followers-only origin page needs a session the
      # remote browser does not have, so receivers must not require it.
      def local_url
        segment = @publication.segment
        return unless segment

        "#{@config.base_url}/segments/#{segment.to_param}"
      end

      def location
        stored = @representation["location"]
        return unless stored.is_a?(Hash)
        return unless valid_coordinate?(stored["longitude"], stored["latitude"])

        {
          "type" => "Place",
          "name" => "Segment start",
          "longitude" => stored["longitude"],
          "latitude" => stored["latitude"]
        }
      end

      def audience
        followers_uri = "#{@actor_uri}/followers"
        if @publication.audience == "followers"
          { "to" => [ followers_uri ], "cc" => [] }
        else
          { "to" => [ PUBLIC_AUDIENCE ], "cc" => [ followers_uri ] }
        end
      end

      def tags
        result = []
        if (slug = @representation["sport_slug"])
          label = Sport.find_by(slug:)&.label || slug.humanize
          result << { "type" => "Note", "name" => "category", "content" => label }
          result << { "type" => "Note", "name" => "sport_slug", "content" => slug }
        end
        result << { "type" => "Note", "name" => "segment_kind", "content" => @representation.fetch("kind", "segment") }
        result + METRIC_TAGS.filter_map do |wire_name, key|
          value = @representation[key]
          next if value.nil?

          { "type" => "Note", "name" => wire_name, "content" => format_metric(key, value) }
        end
      end

      def format_metric(key, value)
        formatted = format("%.6f", Float(value))
        METRE_TAGS.include?(key) ? "#{formatted}m" : formatted
      rescue ArgumentError, TypeError
        raise Unavailable, "publication metric is invalid"
      end

      def attachments
        [].tap do |result|
          if @publication.sanitized_attachment(:route_image)
            result << {
              "type" => "Image",
              "mediaType" => "image/png",
              "name" => "Route image",
              "url" => "#{@publication.object_uri}/media/route-image"
            }
          end
          if @publication.sanitized_attachment(:route_image_dark)
            # The dark variant follows the light one, so a peer that predates
            # the theme property keeps the first Image (DESIGN.md §15.4).
            result << {
              "type" => "Image",
              "mediaType" => "image/png",
              "name" => "Route image (dark)",
              "url" => "#{@publication.object_uri}/media/route-image-dark",
              "allure:theme" => "dark"
            }
          end
          if @publication.sanitized_attachment(:gpx)
            result << {
              "type" => "Document",
              "mediaType" => "application/xml+gpx",
              "name" => "GPX course",
              "url" => "#{@publication.object_uri}/media/gpx"
            }
          end
        end
      end

      def valid_coordinate?(longitude, latitude)
        longitude.is_a?(Numeric) && latitude.is_a?(Numeric) &&
          longitude.to_f.finite? && latitude.to_f.finite? &&
          longitude.between?(-180, 180) && latitude.between?(-90, 90)
      end
    end
  end
end
