# frozen_string_literal: true

require "net/http"
require "uri"

module Workouts
  # Fetches the raster basemap used after owner MapLibre rendering exhausts its
  # bounded retries.
  #
  # The interactive map stays vector (MapLibre + OpenFreeMap style); Ruby has
  # no vector renderer, so the PNG stitches raster tiles showing the same OSM
  # geography. The tile host is operator-configured
  # (`Allure::Maps::Config#raster_template`), so a privacy-strict deployment
  # points it at a self-hosted tile server. Fetching discloses the approximate
  # route bounds and the server IP to that host — the same trade-off the
  # interactive map already makes client-side.
  #
  # Any fetch problem returns nil so the caller falls back to the tile-less
  # rendering instead of failing the workout. Only invalid coordinates raise
  # `ArgumentError`, mirroring `RouteImageRenderer`.
  class RouteBasemapFetcher
    Basemap = Data.define(:png_bytes, :zoom, :x_min, :y_min)

    TILE_SIZE = 256
    MAX_ZOOM = 17
    MIN_ZOOM = 0
    # The canvas is double-density (800x450), so allow one zoom level deeper
    # than strictly needed: the placed basemap then downsamples instead of
    # upscaling and stays sharp. Fetches stay sequential (one connection, with
    # a User-Agent) to respect the tile usage policy.
    MAX_TILES = 32
    MAX_TILE_BYTES = 1.megabyte
    MAX_STITCH_BYTES = 8.megabytes
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10
    USER_AGENT = "AllureRouteImage/1.0"
    MERCATOR_LAT_LIMIT = 85.05112878

    def initialize(segments:, raster_template: nil, http_factory: nil)
      @segments = normalize_segments(segments)
      @raster_template = raster_template || Allure::Maps.config.raster_template
      @http_factory = http_factory || method(:default_http)
    end

    def call
      return nil if crosses_antimeridian?(@segments)

      zoom, x_min, x_max, y_min, y_max = pick_zoom(@segments)
      return nil if zoom.nil?

      tiles = fetch_tiles(zoom, x_min, x_max, y_min, y_max)
      return nil if tiles.nil?

      Basemap.new(stitch(tiles, x_min, x_max, y_min, y_max), zoom, x_min, y_min)
    rescue ArgumentError
      raise
    rescue StandardError
      nil
    end

    # Slippy-map helpers, shared with the renderer so track and tiles agree.
    class << self
      def longitude_to_global_x(longitude, zoom)
        n = 2**zoom * TILE_SIZE
        ((longitude + 180.0) / 360.0 * n)
      end

      def latitude_to_global_y(latitude, zoom)
        clamped = latitude.clamp(-MERCATOR_LAT_LIMIT, MERCATOR_LAT_LIMIT)
        radians = clamped * Math::PI / 180.0
        n = 2**zoom * TILE_SIZE
        ((1.0 - (Math.log(Math.tan(radians) + (1.0 / Math.cos(radians))) / Math::PI)) / 2.0 * n)
      end

      def tile_url(template, zoom:, x:, y:)
        template.to_s.gsub("{z}", zoom.to_s).gsub("{x}", x.to_s).gsub("{y}", y.to_s)
      end
    end

    private

    def normalize_segments(segments)
      normalized = Array(segments).map do |segment|
        points = Array(segment).map do |point|
          longitude, latitude = Array(point)
          longitude = Float(longitude)
          latitude = Float(latitude)
          unless longitude.finite? && latitude.finite? && longitude.between?(-180, 180) && latitude.between?(-90, 90)
            raise ArgumentError, "invalid route coordinate"
          end

          [ longitude, latitude ]
        rescue TypeError, ArgumentError
          raise ArgumentError, "invalid route coordinate"
        end
        raise ArgumentError, "route segments require at least two points" if points.length < 2

        points
      end
      raise ArgumentError, "at least one route segment is required" if normalized.empty?

      normalized
    end

    # Tile stitching cannot wrap the dateline without fetching two ranges;
    # fall back to tile-less for those rare routes instead of drawing wrong.
    def crosses_antimeridian?(segments)
      segments.any? do |segment|
        segment.each_cons(2).any? { |(lon_a, _), (lon_b, _)| (lon_b - lon_a).abs > 180.0 }
      end
    end

    def pick_zoom(segments)
      (MAX_ZOOM).downto(MIN_ZOOM) do |zoom|
        bounds = tile_bounds_for_canvas(segments, zoom)
        x_min, x_max, y_min, y_max = bounds
        count = (x_max - x_min + 1) * (y_max - y_min + 1)
        return [ zoom, x_min, x_max, y_min, y_max ] if count.between?(1, MAX_TILES)
      end
      nil
    end

    # Tiles must cover the whole canvas, not only the route bounding box: the
    # renderer scales the route to fit the canvas, and a route running north to
    # south would otherwise sit on a narrow strip with blank sides. The scale
    # mirrors `RouteImageRenderer#fit_mercator_to_canvas` so the stitched image
    # lands exactly where the renderer places it.
    def tile_bounds_for_canvas(segments, zoom)
      xs = []
      ys = []
      segments.each do |segment|
        segment.each do |longitude, latitude|
          xs << self.class.longitude_to_global_x(longitude, zoom)
          ys << self.class.latitude_to_global_y(latitude, zoom)
        end
      end

      min_x, max_x = xs.minmax
      min_y, max_y = ys.minmax
      route_width = max_x - min_x
      route_height = max_y - min_y
      available_width = RouteImageRenderer::WIDTH - (2 * RouteImageRenderer::PADDING)
      available_height = RouteImageRenderer::HEIGHT - (2 * RouteImageRenderer::PADDING)
      scales = []
      scales << available_width / route_width if route_width.positive?
      scales << available_height / route_height if route_height.positive?
      scale = scales.min || 1.0
      center_x = (min_x + max_x) / 2.0
      center_y = (min_y + max_y) / 2.0
      half_width = RouteImageRenderer::WIDTH / (2.0 * scale)
      half_height = RouteImageRenderer::HEIGHT / (2.0 * scale)

      # Canvas expansion can reach past the world edge at low zooms; clamping
      # keeps the fetch inside the valid tile pyramid instead of asking for
      # tiles that do not exist.
      max_tile = (2**zoom) - 1
      [
        ((center_x - half_width) / TILE_SIZE).floor.clamp(0, max_tile),
        ((center_x + half_width) / TILE_SIZE).floor.clamp(0, max_tile),
        ((center_y - half_height) / TILE_SIZE).floor.clamp(0, max_tile),
        ((center_y + half_height) / TILE_SIZE).floor.clamp(0, max_tile)
      ]
    end

    def fetch_tiles(zoom, x_min, x_max, y_min, y_max)
      tiles = {}
      (x_min..x_max).each do |x|
        (y_min..y_max).each do |y|
          body = fetch_tile(self.class.tile_url(@raster_template, zoom:, x:, y:))
          return nil if body.nil?

          tiles[[ x, y ]] = body
        end
      end
      tiles
    end

    def fetch_tile(url)
      uri = URI.parse(url)
      return nil unless %w[http https].include?(uri.scheme)
      return nil if uri.userinfo.present? || uri.fragment.present?
      return nil if Rails.env.production? && uri.scheme != "https"

      http = @http_factory.call(uri)
      request = Net::HTTP::Get.new(uri.request_uri, { "User-Agent" => USER_AGENT, "Accept" => "image/png,image/*" })
      body = +"".b
      http.request(request) do |response|
        return nil unless response.is_a?(Net::HTTPSuccess)
        return nil unless response.content_type.to_s.start_with?("image/")

        response.read_body do |chunk|
          body << chunk
          return nil if body.bytesize > MAX_TILE_BYTES
        end
      end
      body
    rescue StandardError
      nil
    end

    def default_http(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      http
    end

    def stitch(tiles, x_min, x_max, y_min, y_max)
      rows = (y_min..y_max).map do |y|
        row_tiles = (x_min..x_max).map do |x|
          body = tiles.fetch([ x, y ])
          raise "missing tile" if body.bytesize > MAX_STITCH_BYTES

          image = Vips::Image.new_from_buffer(body, "", access: :sequential)
          raise "invalid tile dimensions" unless image.width == TILE_SIZE && image.height == TILE_SIZE

          image
        end
        Vips::Image.arrayjoin(row_tiles, across: row_tiles.length)
      end
      stitched = Vips::Image.arrayjoin(rows, across: 1)
      bytes = stitched.write_to_buffer(".png")
      raise "stitched basemap too large" if bytes.bytesize > MAX_STITCH_BYTES

      bytes.b
    end
  end
end
