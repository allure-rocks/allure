# frozen_string_literal: true

require "time"
require "uri"

module Federation
  module Parsers
    # Turns an embedded Allure course Note into an immutable normalized value
    # (PLAN_SEGMENTS_FEDERATION.md §10.2). Whole-document violations raise
    # InvalidObject; malformed individual values are skipped and recorded as
    # warnings. The preserved raw object keeps unknown tags and non-Note
    # entries.
    class RemoteSegment
      class InvalidObject < StandardError; end

      PUBLIC_AUDIENCE = "https://www.w3.org/ns/activitystreams#Public"
      MAX_NAME = 120
      MAX_CONTENT = 10_000
      MAX_TAGS = 200
      MAX_AUDIENCE = 200
      MAX_ATTACHMENTS = 4
      MAX_WARNINGS = 50
      SEGMENT_KIND = "segment"
      OBJECT_PATH = %r{\A/api/v1/segment/([^/]+)\z}

      # Wire tag name => canonical course metric key.
      METRIC_TAGS = {
        "distance" => "distance",
        "elevation_gain" => "ascent",
        "elevation_loss" => "descent",
        "average_grade" => "average_grade",
        "match_tolerance" => "match_tolerance"
      }.freeze

      METRE_TAGS = %w[distance elevation_gain elevation_loss match_tolerance].freeze

      METRIC_BOUNDS = {
        "distance" => 0.0..10_000_000.0,
        "ascent" => 0.0..100_000.0,
        "descent" => 0.0..100_000.0,
        "average_grade" => -100.0..100.0,
        "match_tolerance" => 5.0..100.0
      }.freeze

      ATTACHMENT_TYPES = {
        [ "Image", "image/png" ] => "route_image",
        [ "Document", "application/xml+gpx" ] => "gpx"
      }.freeze
      ATTACHMENT_THEMES = %w[light dark].freeze

      Attachment = Data.define(:kind, :remote_url, :media_type, :theme)
      Value = Data.define(
        :object_uri, :attributed_to, :name, :description, :content_html,
        :sport_label, :sport_slug, :published_at, :location, :metrics,
        :warnings, :attachments, :audience, :raw
      )

      def initialize(activity)
        @activity = activity.is_a?(Hash) ? activity : {}
        @object = @activity["object"]
        @warnings = []
      end

      def call
        validate_document!
        parse
      end

      private

      def validate_document!
        raise InvalidObject, "activity object must be embedded" unless @object.is_a?(Hash)
        raise InvalidObject, "object type must be Note" unless @object["type"] == "Note"

        actor = @activity["actor"].to_s
        raise InvalidObject, "activity actor is missing" if actor.blank?
        raise InvalidObject, "object attribution does not match the actor" unless @object["attributedTo"] == actor

        @object_uri = absolute_uri(@object["id"])
        raise InvalidObject, "object id is invalid" unless @object_uri

        validate_segment_path!

        @actor_authority = Allure::Federation::Authority.domain(actor)
        object_authority = Allure::Federation::Authority.domain(@object_uri)
        raise InvalidObject, "object authority does not match the author" unless @actor_authority && @actor_authority == object_authority

        name = @object["name"]
        raise InvalidObject, "object name is missing" unless name.is_a?(String) && name.present?
      end

      # The path alone distinguishes a course from a workout; a trail object is
      # never parsed as a segment and the reciprocal guard lives in RemoteNote.
      def validate_segment_path!
        path = URI.parse(@object_uri).path
        match = OBJECT_PATH.match(path)
        raise InvalidObject, "object is not a course" unless match

        Allure::ShortId.decode(match[1])
      rescue URI::InvalidURIError, ArgumentError
        raise InvalidObject, "object short id is invalid"
      end

      def parse
        name = @object["name"].to_s.strip
        @warnings << "name truncated" if name.length > MAX_NAME
        name = name.truncate(MAX_NAME)

        attachments = parse_attachments
        raise InvalidObject, "course has no GPX attachment" unless attachments.any? { |attachment| attachment.kind == "gpx" }

        published = parse_published
        content = sanitized_content(@object["content"])
        metrics = parse_metrics
        segment_kind = segment_kind_value
        audience_values = audience

        Value.new(
          object_uri: @object_uri,
          attributed_to: @object["attributedTo"],
          name:,
          description: Federation::RemoteText.text(content),
          content_html: content,
          sport_label: sport_label,
          sport_slug: sport_slug,
          published_at: published,
          location: parse_location,
          metrics:,
          warnings: @warnings.first(MAX_WARNINGS),
          attachments:,
          audience: audience_values,
          raw: @object
        )
      end

      def parse_published
        raw = @object["published"]
        raise InvalidObject, "published is required" if raw.blank?

        parsed = parse_time(raw, field: "published")
        raise InvalidObject, "published is invalid" unless parsed

        parsed
      end

      def sanitized_content(value)
        return nil if value.nil?

        raw = value.to_s
        if raw.length > MAX_CONTENT
          @warnings << "content truncated"
          raw = raw.first(MAX_CONTENT)
        end
        Federation::RemoteText.sanitize(raw)
      end

      def segment_kind_value
        value = tag_content("segment_kind")
        raise InvalidObject, "course kind is missing" if value.blank?
        raise InvalidObject, "course kind is unsupported" unless value.strip == SEGMENT_KIND

        SEGMENT_KIND
      end

      def sport_label
        value = tag_content("category")
        value&.strip&.first(120)&.presence
      end

      def sport_slug
        value = tag_content("sport_slug")
        value&.strip&.first(120)&.presence
      end

      def tag_content(name)
        entry = note_tags.find { |tag| tag["name"] == name }
        entry && entry["content"].is_a?(String) ? entry["content"] : nil
      end

      def parse_metrics
        metrics = {}
        note_tags.first(MAX_TAGS).each do |tag|
          key = METRIC_TAGS[tag["name"]]
          next unless key
          next if metrics.key?(key)

          value = metric_value(tag["name"], tag["content"])
          next if value.nil?

          if METRIC_BOUNDS.fetch(key).cover?(value)
            metrics[key] = value
          else
            warn("metric out of range: #{tag['name']}")
          end
        end
        warn("too many tags") if note_tags.length > MAX_TAGS
        metrics
      end

      def metric_value(wire_name, content)
        return nil if content.nil?

        raw = content.to_s.strip
        raw = raw.delete_suffix("m") if METRE_TAGS.include?(wire_name)
        value = Float(raw)
        value.finite? ? value : nil
      rescue ArgumentError, TypeError
        warn("malformed metric: #{wire_name}")
        nil
      end

      def note_tags
        @note_tags ||= Array(@object["tag"]).select do |entry|
          entry.is_a?(Hash) && entry["type"] == "Note" && entry["name"].is_a?(String)
        end
      end

      def parse_attachments
        entries = Array(@object["attachment"])
        warn("too many attachments") if entries.length > MAX_ATTACHMENTS
        seen = []
        entries.first(MAX_ATTACHMENTS).filter_map do |entry|
          next unless entry.is_a?(Hash)

          kind = ATTACHMENT_TYPES[[ entry["type"], entry["mediaType"] ]]
          next unless kind

          theme = attachment_theme(entry)
          next if seen.include?([ kind, theme ])

          url = absolute_uri(entry["url"])
          unless url
            warn("invalid attachment URL")
            next
          end
          # Same confused-deputy guard as RemoteNote: the signed fetch only
          # ever targets the author's own authority.
          unless same_authority?(url)
            warn("attachment authority does not match the author")
            next
          end

          seen << [ kind, theme ]
          Attachment.new(kind:, remote_url: url, media_type: entry["mediaType"], theme:)
        end
      end

      # The image variant, declared by the sender as `allure:theme`. Absent
      # means the historical light image; an unknown value degrades to light
      # with a warning (DESIGN.md §15.4).
      def attachment_theme(entry)
        value = entry["allure:theme"]
        return "light" if value.nil?

        theme = value.to_s
        return theme if ATTACHMENT_THEMES.include?(theme)

        warn("invalid attachment theme")
        "light"
      end

      def same_authority?(url)
        authority = Allure::Federation::Authority.domain(url)
        authority.present? && authority.casecmp?(@actor_authority)
      end

      def parse_location
        value = @object["location"]
        return nil if value.nil?
        return invalid_location unless value.is_a?(Hash)

        longitude = value["longitude"]
        latitude = value["latitude"]
        return invalid_location unless coordinate?(longitude, latitude)

        { "longitude" => Float(longitude), "latitude" => Float(latitude) }
      end

      def invalid_location
        warn("invalid location")
        nil
      end

      def parse_time(value, field:)
        raw = value.to_s
        return nil unless raw.include?("T")

        Time.iso8601(raw).utc
      rescue ArgumentError, TypeError
        warn("invalid #{field}")
        nil
      end

      def audience
        values = list(@activity["to"]) + list(@activity["cc"]) +
          list(@object["to"]) + list(@object["cc"])
        values = values.uniq
        if values.length > MAX_AUDIENCE
          warn("too many audience entries")
          values = values.first(MAX_AUDIENCE)
        end
        values
      end

      def list(value)
        case value
        when String then [ value ]
        when Array then value.select { |entry| entry.is_a?(String) }
        else []
        end
      end

      def absolute_uri(value)
        return nil unless value.is_a?(String) && value.present?

        parsed = URI.parse(value)
        valid = parsed.scheme.in?(%w[http https]) && parsed.host.present? &&
          parsed.userinfo.blank? && parsed.query.blank? && parsed.fragment.blank?
        valid ? value : nil
      rescue URI::InvalidURIError, URI::InvalidComponentError
        nil
      end

      def coordinate?(longitude, latitude)
        longitude.is_a?(Numeric) && latitude.is_a?(Numeric) &&
          longitude.to_f.finite? && latitude.to_f.finite? &&
          longitude.between?(-180, 180) && latitude.between?(-90, 90)
      end

      def warn(message)
        return if @warnings.length >= MAX_WARNINGS

        @warnings << message.to_s.gsub(/\s+/, " ").truncate(160)
      end
    end
  end
end
