# frozen_string_literal: true

module Allure
  module Federation
    module Privacy
      # Projects already-sanitized values through a profile. It deliberately
      # accepts values instead of Workout or Active Storage objects, so a
      # disabled representation has no raw source fallback available.
      class SanitizedPublicationBuilder
        REPRESENTATION_KEYS = %w[
          title description metrics route gpx route_image records device commute weather comments
        ].freeze
        # Settings that shape a representation without naming one.
        STYLE_KEYS = %w[mask_start mask_finish basemap].freeze
        # Accepted but ignored here: local-only profile settings that never
        # reach the federated representation.
        LOCAL_ONLY_KEYS = %w[segment].freeze
        # The photo settings: the candidate projects the frozen photos itself
        # (PLAN_PHOTOS.md §5.3), from copies this builder never sees.
        PHOTO_KEYS = %w[photos photo_captions photo_positions].freeze
        # The device string is free-form in the source file; the published
        # representation is bounded so a long creator cannot bloat a snapshot.
        MAX_DEVICE_LENGTH = 120

        def initialize(settings:, title:, description:, metrics:, track:, gpx:, route_image:, records: {}, device: nil,
                       commute: false, weather: nil)
          @settings = normalize_settings(settings)
          @title = title
          @description = description
          raise ArgumentError, "metrics must be a hash" unless metrics.is_a?(Hash)

          @metrics = metrics.stringify_keys
          @track = track
          @gpx = gpx
          @route_image = route_image
          @records = records.stringify_keys
          @device = device
          @commute = commute == true
          @weather = weather
        end

        def call
          result = {}
          result[:title] = @title if enabled?("title")
          result[:description] = @description if enabled?("description")
          result[:metrics] = permitted_metrics if @settings["metrics"].is_a?(Array)
          result[:track] = @track if enabled?("route")
          result[:gpx] = @gpx if enabled?("gpx")
          result[:route_image] = @route_image if enabled?("route_image")
          result.merge!(@records.slice("record_types", "record_distances")) if enabled?("records")
          result[:device] = bounded_device if enabled?("device")
          # Commute is emitted only when the profile shares it and the workout
          # actually is one: absence is the false value on the wire.
          result[:commute] = true if enabled?("commute") && @commute
          # The weather summary only (PLAN_WEATHER.md §6): never the hourly
          # series, a cell or an instant.
          result[:weather] = sanitized_weather if enabled?("weather")
          # Comments are open unless the profile explicitly closes them: a
          # profile written before the setting existed has no key and keeps
          # them open. Only the closed state is carried.
          result[:comments_closed] = true if @settings["comments"] == false
          result.compact
        end

        private

        def sanitized_weather
          return nil unless @weather.is_a?(Hash)

          summary = @weather.stringify_keys.slice(*Allure::Weather::Summary::KEYS)
          exposure = summary["wind_exposure"]
          summary["wind_exposure"] = exposure.stringify_keys.slice("head", "tail", "cross", "headwind") if exposure.is_a?(Hash)
          summary.compact.presence
        end

        def bounded_device
          device = @device.to_s.strip[0, MAX_DEVICE_LENGTH]
          device.presence
        end

        def normalize_settings(settings)
          unless settings.is_a?(Hash) && settings.keys.map(&:to_s).all? { |key|
            REPRESENTATION_KEYS.include?(key) || STYLE_KEYS.include?(key) || LOCAL_ONLY_KEYS.include?(key) ||
              PHOTO_KEYS.include?(key)
          }
            raise ArgumentError, "invalid publication settings"
          end

          settings.stringify_keys
        end

        def enabled?(key) = @settings.fetch(key, false) == true

        def permitted_metrics
          return {} unless enabled?("metrics") || @settings["metrics"].is_a?(Array)

          allowed = Array(@settings["metrics"]).map(&:to_s)
          @metrics.slice(*allowed)
        end
      end
    end
  end
end
