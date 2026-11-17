# frozen_string_literal: true

require "uri"

module Allure
  module Maps
    # Basemap configuration for the interactive MapLibre map.
    #
    # MapLibre is handed a style document, and that document names its own
    # vector tile, glyph, and sprite endpoints and carries the attribution its
    # provider requires. So there is exactly one thing to configure here: a
    # style URL per theme. Nothing else about the basemap belongs in the
    # application.
    #
    # The default is the OpenFreeMap public instance: no API key, no
    # registration, no cookies, no request limits. It is still a third party,
    # and asking it for tiles discloses the approximate bounds of whatever route
    # is on screen. That is not a regression — the Leaflet map this replaced
    # defaulted to OpenStreetMap raster tiles, which disclosed the same thing —
    # but it is not a privacy-strict posture either. Point these at a
    # self-hosted tile server and no application code changes.
    #
    # See docs/dev/MAPS.md
    class Config
      class InvalidStyleUrl < StandardError; end
      class InvalidRasterTemplate < StandardError; end

      DEFAULT_STYLE_URL = "https://tiles.openfreemap.org/styles/liberty"
      DEFAULT_DARK_STYLE_URL = "https://tiles.openfreemap.org/styles/dark"
      # Raster tiles are the owner image's post-retry fallback and the published
      # image's basemap. The owner's normal path renders the light vector style
      # through MapLibre in headless Chromium; publications fetch this template
      # at publish time and fall back to a tile-less image when it fails.
      DEFAULT_RASTER_TEMPLATE = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
      RASTER_PLACEHOLDERS = %w[{z} {x} {y}].freeze

      attr_reader :style_url, :dark_style_url, :raster_template

      def initialize(style_url: nil, dark_style_url: nil, raster_template: nil)
        light = style_url || ENV["MAP_STYLE_URL"].presence
        dark = dark_style_url || ENV["MAP_STYLE_URL_DARK"].presence
        @raster_template = normalize_template(
          raster_template || ENV["MAP_RASTER_TEMPLATE"].presence || DEFAULT_RASTER_TEMPLATE
        )

        @style_url = normalize(light || DEFAULT_STYLE_URL, "MAP_STYLE_URL")
        @dark_style_url =
          if dark
            normalize(dark, "MAP_STYLE_URL_DARK")
          elsif light
            # A custom light style with no dark counterpart reuses the light one.
            # Falling back to the OpenFreeMap default instead would silently mix
            # two providers, and send route bounds to a third party the operator
            # thought they had configured away.
            @style_url
          else
            normalize(DEFAULT_DARK_STYLE_URL, "MAP_STYLE_URL_DARK")
          end
      end

      # `theme` is a User#theme value, or whatever the layout rendered into
      # `data-bs-theme`. Anything unrecognised gets the light style, which is
      # also what an anonymous visitor sees.
      def style_url_for(theme:)
        theme.to_s == "dark" ? dark_style_url : style_url
      end

      # False when both themes resolve to the same document, which lets the map
      # controller skip the setStyle round trip on a theme toggle.
      def theme_aware? = style_url != dark_style_url

      def secure? = %w[https].include?(URI.parse(style_url).scheme)

      def raster_secure? = URI.parse(raster_probe(raster_template)).scheme == "https"

      def raster_probe(value) = value.to_s.gsub("{z}", "0").gsub("{x}", "0").gsub("{y}", "0")

      private

      def normalize_template(value)
        missing = RASTER_PLACEHOLDERS.reject { |placeholder| value.to_s.include?(placeholder) }
        raise InvalidRasterTemplate, "MAP_RASTER_TEMPLATE must contain {z}, {x} and {y}" if missing.any?

        probe = raster_probe(value)
        uri = URI.parse(probe.strip)

        raise InvalidRasterTemplate, "MAP_RASTER_TEMPLATE must be absolute" if uri.host.blank?
        unless %w[http https].include?(uri.scheme)
          raise InvalidRasterTemplate, "MAP_RASTER_TEMPLATE must be http or https"
        end
        raise InvalidRasterTemplate, "MAP_RASTER_TEMPLATE must not contain credentials" if uri.userinfo.present?
        raise InvalidRasterTemplate, "MAP_RASTER_TEMPLATE must not contain a fragment" if uri.fragment.present?

        value.to_s.strip
      rescue URI::InvalidURIError => error
        raise InvalidRasterTemplate, "MAP_RASTER_TEMPLATE is not a valid URI: #{error.message}"
      end

      def normalize(value, name)
        uri = URI.parse(value.to_s.strip)

        raise InvalidStyleUrl, "#{name} must be absolute, got #{value.inspect}" if uri.host.blank?

        unless %w[http https].include?(uri.scheme)
          raise InvalidStyleUrl, "#{name} must be http or https, got #{uri.scheme.inspect}"
        end

        # Credentials in a style URL would be handed to the browser in a data
        # attribute, which is the same as publishing them.
        raise InvalidStyleUrl, "#{name} must not contain credentials" if uri.userinfo.present?

        uri.to_s
      rescue URI::InvalidURIError => e
        raise InvalidStyleUrl, "#{name} is not a valid URI: #{e.message}"
      end
    end
  end
end
