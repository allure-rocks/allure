# frozen_string_literal: true

module Federation
  module Serializers
    class WorkoutNote
      ACTIVITY_STREAMS_CONTEXT = "https://www.w3.org/ns/activitystreams"
      PUBLIC_AUDIENCE = "#{ACTIVITY_STREAMS_CONTEXT}#Public"
      METRIC_TAG_NAMES = {
        "ascent" => "elevation_gain",
        "descent" => "elevation_loss"
      }.freeze
      METRE_METRICS = %w[distance ascent descent duration moving_time pause_time].freeze

      class Unavailable < StandardError; end

      def initialize(publication:, actor: nil, actor_uri: nil, config: Allure::Federation.config)
        @publication = publication
        @representation = publication.representation.stringify_keys
        @settings = publication.profile_settings.stringify_keys
        @actor_uri = actor&.uri || actor_uri || publication.actor.uri
        @config = config
      end

      def call
        raise Unavailable, "publication is not active" unless @publication.active?
        raise Unavailable, "publication has no retained source" unless @publication.workout

        note = {
          "@context" => ACTIVITY_STREAMS_CONTEXT,
          "id" => @publication.object_uri,
          "type" => "Note",
          "attributedTo" => @actor_uri,
          "name" => name,
          "startTime" => start_time,
          "location" => location,
          "content" => content,
          "url" => "#{@config.base_url}/workouts/#{@publication.workout.to_param}",
          "published" => published_at,
          "to" => audience.fetch("to"),
          "cc" => audience.fetch("cc"),
          "tag" => tags
        }
        note["attachment"] = attachments if attachments.any?
        note
      end

      private

      def name
        return @representation["title"].to_s if @representation["title"].present?

        Sport.find_by(slug: @representation.fetch("sport_slug"))&.label.presence ||
          @representation.fetch("sport_slug").humanize
      end

      def start_time
        Time.iso8601(@representation.fetch("started_at")).utc.iso8601
      rescue ArgumentError, TypeError, KeyError
        raise Unavailable, "publication start time is invalid"
      end

      def published_at
        @publication.published_at.utc.iso8601
      end

      def location
        longitude, latitude = location_coordinates
        {
          "type" => "Place",
          "name" => "Sanitized route",
          "longitude" => longitude,
          "latitude" => latitude
        }
      end

      def location_coordinates
        stored = @representation["location"]
        if stored.is_a?(Hash)
          longitude = stored["longitude"]
          latitude = stored["latitude"]
          return [ longitude, latitude ] if valid_coordinate?(longitude, latitude)
        end

        coordinates = @representation.dig("track", "features", 0, "geometry", "coordinates", 0)
        return coordinates if coordinates.is_a?(Array) && valid_coordinate?(*coordinates)

        raise Unavailable, "publication has no sanitized location"
      end

      def valid_coordinate?(longitude, latitude)
        longitude.is_a?(Numeric) && latitude.is_a?(Numeric) &&
          longitude.to_f.finite? && latitude.to_f.finite? &&
          longitude.between?(-180, 180) && latitude.between?(-90, 90)
      end

      def content
        values = [ @representation["title"], @representation["description"] ]
          .filter_map { |value| value.to_s.presence }
        values = [ name ] if values.empty?
        values.map { |value| ERB::Util.html_escape(value) }.join("<br>")
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
        category = {
          "type" => "Note",
          "name" => "category",
          "content" => Sport.find_by(slug: @representation.fetch("sport_slug"))&.label || @representation.fetch("sport_slug").humanize
        }
        [ category ] + metric_tags + record_tags + device_tags + commute_tags + weather_tags + comments_tags
      end

      def metric_tags
        @representation.fetch("metrics", {}).filter_map do |key, value|
          next if value.nil?

          {
            "type" => "Note",
            "name" => METRIC_TAG_NAMES.fetch(key.to_s, key.to_s),
            "content" => format_metric(key.to_s, value)
          }
        end
      end

      # Record markers travel as two comma-separated token lists, not metrics:
      # they carry no numeric value, only what the workout held at publish time.
      def record_tags
        [
          [ "record_types", Array(@representation["record_types"]) ],
          [ "record_distances", Array(@representation["record_distances"]) ]
        ].filter_map do |name, tokens|
          tokens = tokens.select { |token| token.is_a?(String) && token.present? }
          next if tokens.empty?

          { "type" => "Note", "name" => name, "content" => tokens.join(",") }
        end
      end

      # The recording device or software travels as one dedicated tag, only
      # when the profile shared it. It is a display value, never a metric.
      def device_tags
        device = @representation["device"]
        return [] unless device.is_a?(String) && device.present?

        [ { "type" => "Note", "name" => "device", "content" => device } ]
      end

      # Commute is presence-only: the tag exists when the snapshot says the
      # workout is a commute, and absence means it is not shared or not one.
      def commute_tags
        return [] unless @representation["commute"] == true

        [ { "type" => "Note", "name" => "commute", "content" => "true" } ]
      end

      # The weather summary, only when the profile shared it
      # (docs/dev/WEATHER.md): short SI lists, never an hourly value.
      def weather_tags
        Allure::Weather::NoteTags.encode(@representation["weather"]).map do |name, content|
          { "type" => "Note", "name" => name, "content" => content }
        end
      end

      # A profile that closed comments says so on the wire, so a receiving
      # instance never offers a composer this one would refuse; absence means
      # open (docs/dev/COMMENTS.md).
      def comments_tags
        return [] unless @representation["comments_closed"] == true

        [ { "type" => "Note", "name" => "comments", "content" => "closed" } ]
      end

      def format_metric(key, value)
        formatted = format("%.6f", Float(value))
        METRE_METRICS.include?(key) ? "#{formatted}m" : formatted
      rescue ArgumentError, TypeError
        raise Unavailable, "publication metric is invalid"
      end

      def attachments
        [].tap do |result|
          if @settings["route_image"] == true && @publication.sanitized_attachment(:route_image)
            result << {
              "type" => "Image",
              "mediaType" => "image/png",
              "name" => "Route image",
              "url" => "#{@publication.object_uri}/media/route-image"
            }
          end
          if @settings["route_image"] == true && @publication.sanitized_attachment(:route_image_dark)
            # The second Image is the dark variant. It is advertised after the
            # light one so a peer that predates the theme property keeps the
            # first Image as its route image (DESIGN.md §15.4).
            result << {
              "type" => "Image",
              "mediaType" => "image/png",
              "name" => "Route image (dark)",
              "url" => "#{@publication.object_uri}/media/route-image-dark",
              "allure:theme" => "dark"
            }
          end
          if @settings["gpx"] == true && @publication.sanitized_attachment(:gpx)
            result << {
              "type" => "Document",
              "mediaType" => "application/xml+gpx",
              "name" => "GPX route",
              "url" => "#{@publication.object_uri}/media/gpx"
            }
          end
        end
      end
    end
  end
end
