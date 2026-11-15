# frozen_string_literal: true

require "json"
require "tempfile"
require "vips"

module Workouts
  class MaplibreRouteImageRenderer
    WIDTH = 1_600
    HEIGHT = 900
    DEFAULT_TIMEOUT_MS = 30_000
    MAX_TIMEOUT_MS = 120_000
    MAX_OUTPUT_BYTES = 12.megabytes
    PROCESS_GRACE_SECONDS = 10

    class RenderingError < StandardError; end

    # The image surface: the light PNG and the dark PNG share geometry and
    # therefore use the same style; only the page surface, marker ring and
    # chevron halo change (DESIGN.md §15.4).
    THEMES = %w[light dark].freeze

    def initialize(
      segments:,
      line_colour:,
      smoothing: nil,
      theme: "light",
      style_url: Allure::Maps.config.style_url,
      virtual_basemap: nil,
      allowed_origins: ENV.fetch("ROUTE_IMAGE_MAP_ORIGINS", "").split(","),
      timeout_ms: ENV.fetch("ROUTE_IMAGE_RENDER_TIMEOUT_MS", DEFAULT_TIMEOUT_MS),
      node_binary: ENV.fetch("NODE_BINARY", "node"),
      runner_path: Rails.root.join("script/render-static-route"),
      public_root: Rails.public_path,
      process_environment: {}
    )
      @payload = {
        segments:,
        lineColour: line_colour,
        theme: theme.to_s,
        allowedOrigins: allowed_origins.map(&:strip).reject(&:empty?).uniq
      }
      @public_root = public_root
      # A virtual world replaces the tile style with its own map image, handed
      # over as a data URL so the renderer needs no network and no origin
      # exception (docs/dev/VIRTUAL-PLATFORMS.md).
      if virtual_basemap
        raise ArgumentError, "invalid virtual basemap" unless virtual_basemap.is_a?(Allure::Virtual::Basemap)

        @payload[:virtualBasemap] = virtual_basemap_payload(virtual_basemap)
      else
        @payload[:styleUrl] = style_url
      end
      @payload[:smoothing] = smoothing.to_s if smoothing.present?
      if smoothing.present? && !Allure::Geometry::Smoothing.valid_level?(smoothing)
        raise ArgumentError, "invalid smoothing level"
      end
      raise ArgumentError, "invalid route image theme" unless THEMES.include?(@payload[:theme])
      @timeout_ms = Integer(timeout_ms)
      raise ArgumentError, "invalid route image render timeout" unless @timeout_ms.between?(1_000, MAX_TIMEOUT_MS)

      @node_binary = node_binary.to_s
      @runner_path = runner_path.to_s
      @process_environment = process_environment
    rescue TypeError, ArgumentError => error
      raise ArgumentError, error.message
    end

    def call
      input = Tempfile.new("allure-maplibre-input", binmode: true)
      output = Tempfile.new([ "allure-maplibre-route", ".png" ], binmode: true)
      log = Tempfile.new("allure-maplibre-log", binmode: true)
      input.write(JSON.generate(@payload))
      input.rewind

      status = run_process(input:, output:, log:)
      unless status.success?
        raise RenderingError, "MapLibre route image rendering failed: #{process_log(log)}"
      end

      validate_output!(output)
      output.rewind
      output
    rescue RenderingError
      output&.close!
      raise
    rescue StandardError => error
      output&.close!
      raise RenderingError, "MapLibre route image rendering failed", cause: error
    ensure
      input&.close!
      log&.close!
    end

    private

    # The world image read once into the payload. The runner is a separate
    # process with no access to the application's public directory, and a data
    # URL keeps the render offline and outside the origin allowlist.
    def virtual_basemap_payload(basemap)
      path = Pathname(@public_root).join(basemap.image)
      {
        image: "data:image/webp;base64,#{Base64.strict_encode64(path.binread)}",
        coordinates: basemap.coordinates,
        background: basemap.background,
        darkBackground: basemap.dark_background,
        attribution: basemap.attribution
      }
    end

    def run_process(input:, output:, log:)
      pid = Process.spawn(
        @process_environment,
        @node_binary,
        @runner_path,
        "--timeout",
        @timeout_ms.to_s,
        output.path,
        in: input.path,
        out: log.path,
        err: log.path,
        pgroup: true
      )
      status = wait_for(pid)
      terminate_process_group(pid) unless status.success?
      status
    rescue RenderingError
      terminate_process_group(pid)
      raise
    end

    def wait_for(pid)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + (@timeout_ms / 1_000.0) + PROCESS_GRACE_SECONDS
      loop do
        waited = Process.waitpid2(pid, Process::WNOHANG)
        return waited.last if waited
        raise RenderingError, "MapLibre route image rendering timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep 0.05
      end
    end

    def terminate_process_group(pid)
      return unless pid

      Process.kill("TERM", -pid)
      sleep 0.1
      Process.kill("KILL", -pid)
    rescue Errno::ESRCH
      nil
    ensure
      begin
        Process.waitpid(pid) if pid
      rescue Errno::ECHILD
        nil
      end
    end

    def validate_output!(output)
      size = output.size
      raise RenderingError, "MapLibre renderer returned an empty image" if size.zero?
      raise RenderingError, "MapLibre renderer returned an oversized image" if size > MAX_OUTPUT_BYTES

      output.rewind
      raise RenderingError, "MapLibre renderer returned a non-PNG image" unless output.read(8) == "\x89PNG\r\n\x1A\n".b

      image = Vips::Image.new_from_file(output.path, access: :sequential)
      return if image.width == WIDTH && image.height == HEIGHT

      raise RenderingError, "MapLibre renderer returned #{image.width}x#{image.height}; expected #{WIDTH}x#{HEIGHT}"
    rescue Vips::Error => error
      raise RenderingError, "MapLibre renderer returned an invalid PNG", cause: error
    end

    def process_log(log)
      log.rewind
      log.read(2_000).presence || "renderer exited without an error message"
    end
  end
end
