# frozen_string_literal: true

module Allure
  module Metrics
    # The Rack endpoint mounted at /metrics. It deliberately bypasses
    # ApplicationController — no session, locale, browser gate, CSRF, or layout
    # — because a Prometheus scraper is not a browser; /up follows the same
    # principle. When METRICS_TOKEN is unset the endpoint answers 404, so an
    # instance without metrics configured does not even confirm the route.
    #
    # Collection runs only after authorization: an unauthenticated or
    # wrong-token scrape must not pay for the aggregate queries.
    class Endpoint
      CONTENT_TYPE = "text/plain; version=0.0.4; charset=utf-8"

      def call(env)
        return not_found unless Config.enabled?
        return unauthorized unless authorized?(Rack::Request.new(env))

        Yabeda.collect!
        body = Prometheus::Client::Formats::Text.marshal(Yabeda::Prometheus.registry)
        unless Allure::Funding.enabled?
          # A previously enabled gauge stays in the process registry. The
          # master switch must also hide its HELP/TYPE and cached samples.
          body = body.lines.reject { |line| line.match?(/\A(?:# (?:HELP|TYPE) )?allure_funding_contributions\b/) }.join
        end
        [ 200, headers(CONTENT_TYPE), [ body.to_s ] ]
      end

      private

      def authorized?(request)
        provided = request.get_header("HTTP_AUTHORIZATION").to_s[/\ABearer (.+)\z/i, 1].to_s
        return false if provided.empty?

        ActiveSupport::SecurityUtils.secure_compare(provided, Config.token)
      end

      def not_found = [ 404, headers, [ "Not Found\n" ] ]

      def unauthorized
        [ 401, headers.merge("www-authenticate" => "Bearer"), [ "Unauthorized\n" ] ]
      end

      # Rack 3 requires lowercase header names; a mixed-case "Cache-Control"
      # would not satisfy Rack::ETag's lowercase check and the middleware would
      # append its own default cache directive.
      def headers(content_type = "text/plain; charset=utf-8")
        {
          "content-type" => content_type,
          "cache-control" => "no-store",
          "x-content-type-options" => "nosniff"
        }
      end
    end
  end
end
