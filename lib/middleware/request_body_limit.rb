# frozen_string_literal: true

module Allure
  # Refuses a request body larger than its endpoint accepts before Rails
  # parses it (PLAN_IMPORT_SOURCES.md §3.2). Puma has already buffered the
  # body by then, within its own server-wide `http_content_length_limit`; this
  # keeps a small form from carrying gigabytes into the multipart parser, a
  # second copy on disk, and the application. Only the reverse proxy refuses
  # before anything reaches the container.
  #
  # Inserted first in the middleware stack: `Rack::MethodOverride` already
  # reads form bodies. Built once at boot, so the endpoint limits read the
  # application's constants on each request instead of holding them.
  class RequestBodyLimit
    # Multipart boundaries, part headers and the form's other fields.
    OVERHEAD_BYTES = 64 * 1024 * 1024
    DEFAULT_BYTES = 32 * 1024 * 1024

    Rule = Data.define(:method, :path, :bytes)

    def self.rules
      archive = Allure::StravaArchive::MAX_BYTES + OVERHEAD_BYTES
      [
        Rule.new(method: "POST", path: "/workout_imports/strava_archive", bytes: archive),
        Rule.new(method: "POST", path: "/api/rest/v1/imports", bytes: archive),
        Rule.new(method: "POST", path: "/workout_imports", bytes: Workouts::ArchiveReader::MAX_SOURCE_BYTES + OVERHEAD_BYTES)
      ]
    end

    # The largest body any endpoint accepts, which Puma's server-wide limit
    # must allow.
    def self.max_bytes = rules.map(&:bytes).max

    def initialize(app)
      @app = app
    end

    def call(env)
      size = body_size(env)
      return too_large if size && size > limit_for(env)

      @app.call(env)
    end

    private

    def limit_for(env)
      method = env["REQUEST_METHOD"]
      path = env["PATH_INFO"].to_s.chomp("/")
      rule = self.class.rules.find { |candidate| candidate.method == method && candidate.path == path }
      rule ? rule.bytes : DEFAULT_BYTES
    end

    # The declared length, else the size of what Puma buffered (a chunked
    # body has no length header).
    def body_size(env)
      declared = env["CONTENT_LENGTH"]
      return Integer(declared, 10) if declared.present?

      input = env["rack.input"]
      input.size if input.respond_to?(:size)
    rescue ArgumentError
      nil
    end

    def too_large
      [ 413, { "content-type" => "text/plain; charset=utf-8", "connection" => "close" }, [ "Content Too Large\n" ] ]
    end
  end
end
