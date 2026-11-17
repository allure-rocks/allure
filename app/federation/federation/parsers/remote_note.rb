# frozen_string_literal: true

require "time"
require "uri"

module Federation
  module Parsers
    # Turns an embedded Allure Note into an immutable normalized value
    # (docs/dev/FEDERATION.md). Whole-document violations raise InvalidObject; malformed
    # individual values are skipped and recorded as warnings. The preserved
    # raw object keeps unknown tags and non-Note entries.
    class RemoteNote
      class InvalidObject < StandardError; end

      PUBLIC_AUDIENCE = "https://www.w3.org/ns/activitystreams#Public"
      MAX_TITLE = 255
      MAX_CONTENT = 10_000
      MAX_TAGS = 200
      MAX_AUDIENCE = 200
      MAX_ATTACHMENTS = 4
      MAX_WARNINGS = 50
      MAX_RECORDS = 32
      MAX_RECORD_CONTENT = 512
      MAX_RECORD_TOKEN = 16
      MAX_DEVICE = 120

      # Wire tag name => canonical metric key.
      METRIC_TAGS = {
        "distance" => "distance",
        "duration" => "duration",
        "moving_time" => "moving_time",
        "pause_time" => "pause_time",
        "elevation_gain" => "ascent",
        "elevation_loss" => "descent",
        "min_elevation" => "min_elevation",
        "max_elevation" => "max_elevation",
        "average_speed" => "average_speed",
        "max_speed" => "max_speed",
        "average_pace" => "average_pace",
        "best_pace" => "best_pace",
        "grade_adjusted_pace" => "grade_adjusted_pace",
        "average_heart_rate" => "average_heart_rate",
        "max_heart_rate" => "max_heart_rate",
        "average_cadence" => "average_cadence",
        "max_cadence" => "max_cadence",
        "average_power" => "average_power",
        "max_power" => "max_power",
        "calories" => "calories"
      }.freeze

      # The legacy contract suffixes these with "m" even though duration and
      # moving time are seconds.
      METRE_TAGS = %w[distance duration moving_time pause_time elevation_gain elevation_loss].freeze

      METRIC_BOUNDS = {
        "distance" => 0.0..10_000_000.0,
        "duration" => 0.0..31_536_000.0,
        "moving_time" => 0.0..31_536_000.0,
        "pause_time" => 0.0..31_536_000.0,
        "ascent" => 0.0..100_000.0,
        "descent" => 0.0..100_000.0,
        "min_elevation" => -500.0..10_000.0,
        "max_elevation" => -500.0..10_000.0,
        "average_speed" => 0.0..200.0,
        "max_speed" => 0.0..300.0,
        "average_pace" => 0.0..86_400.0,
        "best_pace" => 0.0..86_400.0,
        "grade_adjusted_pace" => 0.0..86_400.0,
        "average_heart_rate" => 0.0..300.0,
        "max_heart_rate" => 0.0..300.0,
        "average_cadence" => 0.0..300.0,
        "max_cadence" => 0.0..300.0,
        "average_power" => 0.0..5_000.0,
        "max_power" => 0.0..5_000.0,
        "calories" => 0.0..100_000.0
      }.freeze

      ATTACHMENT_TYPES = {
        [ "Image", "image/png" ] => "route_image",
        [ "Document", "application/xml+gpx" ] => "gpx"
      }.freeze
      ATTACHMENT_THEMES = %w[light dark].freeze

      Attachment = Data.define(:kind, :remote_url, :media_type, :theme)
      Value = Data.define(
        :object_uri, :attributed_to, :title, :description, :content_html,
        :sport_label, :started_at, :published_at, :location, :metrics,
        :record_types, :record_distances, :device, :commute, :weather, :comments_closed,
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
        raise InvalidObject, "object is not a workout" if segment_path?(@object_uri)

        @actor_authority = Allure::Federation::Authority.domain(actor)
        object_authority = Allure::Federation::Authority.domain(@object_uri)
        raise InvalidObject, "object authority does not match the author" unless @actor_authority && @actor_authority == object_authority

        name = @object["name"]
        raise InvalidObject, "object name is missing" unless name.is_a?(String) && name.present?
      end

      def parse
        title = @object["name"].to_s
        warn("title truncated") if title.length > MAX_TITLE
        title = title[0, MAX_TITLE]

        content = @object["content"]
        parsed_content = sanitized_content(content)

        metrics = parse_metrics
        record_types = parse_record_tokens("record_types", Record::TYPES)
        record_distances = parse_record_tokens("record_distances", Allure::Gpx::BestEfforts::DISTANCES.keys)
        device = parse_device
        commute = parse_commute
        weather = parse_weather
        comments_closed = parse_comments_closed
        attachment_values = parse_attachments
        # Evaluated before the Value so its warning is part of the snapshot:
        # keyword arguments are read left to right, and `warnings` comes first.
        audience_values = audience

        Value.new(
          object_uri: @object_uri,
          attributed_to: @activity["actor"],
          title:,
          description: RemoteText.text(parsed_content),
          content_html: parsed_content,
          sport_label: sport_label,
          started_at: parse_time(@object["startTime"], field: "startTime"),
          published_at: parse_time(@object["published"], field: "published"),
          location: parse_location,
          metrics:,
          record_types:,
          record_distances:,
          device:,
          commute:,
          weather:,
          comments_closed:,
          warnings: @warnings.first(MAX_WARNINGS),
          attachments: attachment_values,
          audience: audience_values,
          raw: @object
        )
      end

      # Record markers are two dedicated Note tags with a comma-separated token
      # list, not metrics. Unknown or oversized tokens are skipped with a
      # warning; the first occurrence of a token wins.
      def parse_record_tokens(name, allowlist)
        tag = note_tags.find { |entry| entry["name"] == name }
        content = tag && tag["content"]
        return [] unless content.is_a?(String)

        raw = content.to_s
        warn("#{name} truncated") if raw.length > MAX_RECORD_CONTENT
        tokens = raw[0, MAX_RECORD_CONTENT].split(",").map(&:strip).reject(&:empty?)
        warn("too many #{name} tokens") if tokens.length > MAX_RECORDS
        tokens = tokens.first(MAX_RECORDS)

        seen = []
        tokens.filter_map do |token|
          if token.length > MAX_RECORD_TOKEN || !allowlist.include?(token)
            warn("invalid #{name} token")
            next
          end
          next if seen.include?(token)

          seen << token
          token
        end
      end

      def sanitized_content(value)
        return if value.nil?

        raw = value.to_s
        warn("content truncated") if raw.length > MAX_CONTENT
        RemoteText.sanitize(raw[0, MAX_CONTENT])
      end

      def sport_label
        tag = note_tags.find { |entry| entry["name"] == "category" }
        content = tag && tag["content"]
        content.is_a?(String) ? content.strip[0, 120].presence : nil
      end

      # The recording device or software travels as one dedicated tag, like the
      # sport category. It is a bounded display value, never a metric; a
      # malformed or oversized value is skipped or truncated with a warning.
      def parse_device
        tag = note_tags.find { |entry| entry["name"] == "device" }
        content = tag && tag["content"]
        return nil unless content.is_a?(String)

        raw = content.to_s.strip
        warn("device truncated") if raw.length > MAX_DEVICE
        raw[0, MAX_DEVICE].presence
      end

      # Commute is a presence flag: the tag exists only when the workout is a
      # commute, but `true`/`false`/`1`/`0` are all understood so a peer can
      # also state it explicitly. Anything else is ignored with a warning.
      def parse_commute
        tag = note_tags.find { |entry| entry["name"] == "commute" }
        content = tag && tag["content"]
        return nil unless content.is_a?(String)

        case content.strip.downcase
        when "true", "1" then true
        when "false", "0" then false
        else
          warn("invalid commute value")
          nil
        end
      end

      # The origin's profile closed comments on this publication
      # (docs/dev/COMMENTS.md). Presence-only: `closed` is the one value, an
      # explicit `open` is the default and anything else is a warning that
      # keeps comments open.
      def parse_comments_closed
        tag = note_tags.find { |entry| entry["name"] == "comments" }
        content = tag && tag["content"]
        return nil unless content.is_a?(String)

        case content.strip.downcase
        when "closed" then true
        when "open" then nil
        else
          warn("invalid comments value")
          nil
        end
      end

      def parse_metrics
        metrics = {}
        note_tags.each_with_index do |tag, index|
          break if index >= MAX_TAGS

          name = tag["name"]
          canonical = METRIC_TAGS[name]
          next unless canonical
          if metrics.key?(canonical)
            warn("duplicate metric: #{name}")
            next
          end

          value = metric_value(name, tag["content"])
          next unless value

          warning = "metric out of range: #{name}"
          if METRIC_BOUNDS.fetch(canonical).cover?(value)
            metrics[canonical] = value
          else
            warn(warning)
          end
        end
        if note_tags.length > MAX_TAGS
          warn("too many tags")
        end
        metrics
      end

      def metric_value(wire_name, content)
        return if content.nil?

        raw = content.to_s.strip
        raw = raw.delete_suffix("m") if METRE_TAGS.include?(wire_name)
        value = Float(raw)
        return unless value.finite?

        value
      rescue ArgumentError, TypeError
        warn("malformed metric: #{wire_name}")
        nil
      end

      # The weather summary (docs/dev/WEATHER.md): the first occurrence of each
      # tag counts; malformed values, or a summary that is not plausible as a
      # whole, are dropped with a warning.
      def parse_weather
        contents = {}
        note_tags.each do |entry|
          name = entry["name"]
          next unless Allure::Weather::NoteTags::NAMES.include?(name) && !contents.key?(name)

          contents[name] = entry["content"]
        end
        Allure::Weather::NoteTags.decode(contents, warn: ->(message) { warn(message) })
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
          # The fetch is signed with a local actor's key, so an attachment on
          # another authority would turn this instance into a confused deputy
          # against a third party's followers-only media (docs/dev/FEDERATION.md).
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
      # with a warning, so a future variant never blocks the note.
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
        location = @object["location"]
        return if location.nil?

        unless location.is_a?(Hash)
          warn("invalid location")
          return
        end

        longitude = location["longitude"]
        latitude = location["latitude"]
        if coordinate?(longitude, latitude)
          { "longitude" => longitude.to_f, "latitude" => latitude.to_f }
        else
          warn("invalid location")
          nil
        end
      end

      # A space-separated timestamp is the documented external-peer trap; the
      # strict Allure profile always emits a "T".
      def parse_time(value, field:)
        return if value.nil?

        raw = value.to_s
        unless raw.include?("T")
          warn("invalid #{field}")
          return
        end

        Time.iso8601(raw).utc
      rescue ArgumentError, TypeError
        warn("invalid #{field}")
        nil
      end

      def audience
        entries = (list(@activity["to"]) + list(@activity["cc"]) + list(@object["to"]) + list(@object["cc"])).uniq
        if entries.length > MAX_AUDIENCE
          warn("too many audience entries")
          entries = entries.first(MAX_AUDIENCE)
        end
        entries
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

      # The dedicated course path is never a workout object; the reciprocal
      # guard lives in RemoteSegment.
      def segment_path?(uri)
        URI.parse(uri).path.start_with?("/api/v1/segment/")
      rescue URI::InvalidURIError
        false
      end

      def coordinate?(longitude, latitude)
        longitude.is_a?(Numeric) && latitude.is_a?(Numeric) &&
          longitude.to_f.finite? && latitude.to_f.finite? &&
          longitude.between?(-180, 180) && latitude.between?(-90, 90)
      end

      def warn(message)
        @warnings << message.to_s.gsub(/\s+/, " ").truncate(160) unless @warnings.length >= MAX_WARNINGS
      end
    end
  end
end
