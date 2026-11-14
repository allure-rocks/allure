# frozen_string_literal: true

require "uri"

module Allure
  # The origins the Content-Security-Policy grants beyond this one
  # (config/initializers/content_security_policy.rb), read from the
  # configuration the browser actually reaches:
  #
  # - `connect`: the map styles' hosts, from which MapLibre fetches the style,
  #   tiles, glyphs and sprites, and `ROUTE_IMAGE_MAP_ORIGINS`, the other hosts
  #   a custom style loads from (the route-image renderer reads it too);
  # - `form`: the enabled identity providers, to which a sign-in form's POST
  #   redirects, and the enabled funding providers' hosted portals, to which
  #   the portal form's POST redirects (Chrome checks form-action against the
  #   redirect too);
  # - every directive: `CONTENT_SECURITY_POLICY_SOURCES`, extra origins for
  #   whatever else the browser must reach, such as a provider whose
  #   authorization endpoint is not on its issuer's origin.
  #
  # In development, Vite's hot-reload WebSocket is allowed too.
  module ContentSecurityPolicy
    DIRECTIVES = %i[connect img form].freeze

    module_function

    def sources(directive, env: ENV, development: Rails.env.development?)
      raise ArgumentError, "unknown directive #{directive.inspect}" unless DIRECTIVES.include?(directive)

      own = case directive
      when :connect then map_origins(env) + (development ? %w[ws: wss:] : [])
      when :form then provider_origins + funding_origins
      else []
      end
      (own + extra_sources(env)).uniq
    end

    def map_origins(env)
      config = Allure::Maps::Config.new
      styles = [ config.style_url, config.dark_style_url ]
      (styles + env.fetch("ROUTE_IMAGE_MAP_ORIGINS", "").split(",")).filter_map { origin(it) }
    end

    def provider_origins
      Allure::Auth::Providers.enabled.filter_map { origin(it.issuer) }
    end

    # The hosted management portals of the enabled funding providers: the
    # portal form POSTs to this origin and the browser follows its redirect.
    def funding_origins
      Allure::Funding::Providers.enabled.filter_map do |provider|
        origin(provider.portal_origin) if provider.respond_to?(:portal_origin)
      end
    end

    # Space- or comma-separated origins; anything that is not an http(s)
    # origin is ignored rather than widening the policy.
    def extra_sources(env)
      env.fetch("CONTENT_SECURITY_POLICY_SOURCES", "").split(/[\s,]+/).filter_map { origin(it) }
    end

    def origin(url)
      uri = URI.parse(url.to_s.strip)
      return nil unless %w[http https].include?(uri.scheme) && uri.host.present?

      default_port = uri.scheme == "https" ? 443 : 80
      port = uri.port && uri.port != default_port ? ":#{uri.port}" : ""
      "#{uri.scheme}://#{uri.host.downcase}#{port}"
    rescue URI::InvalidURIError
      nil
    end
  end
end
