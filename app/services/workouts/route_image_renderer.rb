# frozen_string_literal: true

require "base64"
require "image_processing/vips"
require "tempfile"

module Workouts
  class RouteImageRenderer
    # Double-density canvas: timeline cards and the detail view display the PNG
    # below its native size, so 2x keeps the track, streets and attribution
    # crisp on retina screens for ~300 KB per image.
    WIDTH = 800
    HEIGHT = 450
    PADDING = 32
    MAX_POINTS = 2_000
    LINE_WIDTH = 8
    DOT_RADIUS = 12
    FINISH_DOT_RADIUS = 14
    DOT_STROKE = 4
    CHECKER_SIZE = 6
    ATTRIBUTION_FONT_SIZE = 20
    BACKGROUND_COLOUR = "#f4f6fa"
    # Dark variant surface, matching the application's dark body background
    # (Tabler `--tblr-body-bg` #171717). The track colour is theme-invariant:
    # sport identity never uses colour, and the brand primary stays legible on
    # both surfaces (DESIGN.md §15.4).
    DARK_BACKGROUND_COLOUR = "#171717"
    SURFACE_COLOURS = {
      "light" => BACKGROUND_COLOUR,
      "dark" => DARK_BACKGROUND_COLOUR
    }.freeze
    THEMES = SURFACE_COLOURS.keys.freeze
    # One rose track for every sport (DESIGN.md §6/§15.4): sport identity is
    # icon + text, never colour. The interactive map draws the brand primary,
    # which is this same value; the parity spec keeps the two from drifting.
    TRACK_COLOUR = "#c5426c"
    START_COLOUR = "#2fb344"
    FINISH_CHECKER_DARK = "#111827"
    FINISH_CHECKER_LIGHT = "#ffffff"
    # Full arrow with a shaft and open head, offset 12 px outside detected
    # loops (right otherwise). A surface halo keeps its coloured stroke legible.
    CHEVRON_PATH = "M -7 0 L 7 0 M 2.5 -4 L 7 0 L 2.5 4"
    CHEVRON_SURFACE = "#ffffff"
    CHEVRON_SURFACES = {
      "light" => CHEVRON_SURFACE,
      "dark" => DARK_BACKGROUND_COLOUR
    }.freeze
    CHEVRON_HALO_WIDTH = 2.8
    CHEVRON_CORE_WIDTH = 1.5
    MIN_DIRECTION_COUNT = 3
    # The endpoint ring separates the start dot and the checkered finish from
    # whatever lies under them: white on the light surface, the dark surface on
    # the dark render.
    DOT_STROKES = { "light" => "#ffffff", "dark" => DARK_BACKGROUND_COLOUR }.freeze
    ATTRIBUTION_TEXT = "© OpenStreetMap contributors"
    ATTRIBUTION_FILLS = { "light" => "#333333", "dark" => "#e5e5e5" }.freeze
    ATTRIBUTION_STROKES = { "light" => "#ffffff", "dark" => DARK_BACKGROUND_COLOUR }.freeze
    COLOUR_PATTERN = /\A#[0-9a-f]{6}\z/i
    SVG_RENDER_MUTEX = Mutex.new

    class RenderingError < StandardError; end

    # `basemap` is a `RouteBasemapFetcher::Basemap` (stitched raster tiles plus
    # their zoom and tile origin). When present the track is projected into the
    # same WebMercator pixel space so it lands on the right streets; when nil
    # the legacy tile-less equirectangular rendering is used (publications and
    # the fetch-failure fallback).
    #
    # `theme` selects the surface the image is drawn for. The dark variant is
    # tile-less only: the raster basemap is a light OSM render, so a dark image
    # never composites it (DESIGN.md §15.4).
    #
    # `smoothing` is a display-only level (`light`, `medium`, `strong`) from
    # `Allure::Geometry::Smoothing`; nil draws the geometry as recorded. Course
    # (segment) images pass `medium`; workout images pass nothing.
    #
    # `background` replaces the theme's own surface: a virtual world's fallback
    # image is drawn in the world's colour instead of the application surface
    # (PLAN_VIRTUAL.md). `attribution` replaces the OpenStreetMap credit for the
    # same reason: a world image carries Zwift's map, not OSM data.
    def initialize(segments:, line_colour:, basemap: nil, smoothing: nil, theme: "light", background: nil,
                   attribution: nil)
      @segments = normalize_segments(segments)
      @line_colour = line_colour.to_s
      @basemap = basemap
      @smoothing = smoothing.presence&.to_s
      @theme = theme.to_s
      @background = background.presence&.to_s
      @attribution = attribution.presence&.to_s
      raise ArgumentError, "invalid line colour" unless COLOUR_PATTERN.match?(@line_colour)
      raise ArgumentError, "invalid smoothing level" if @smoothing && !Allure::Geometry::Smoothing.valid_level?(@smoothing)
      raise ArgumentError, "invalid route image theme" unless THEMES.include?(@theme)
      raise ArgumentError, "invalid route image background" if @background && !COLOUR_PATTERN.match?(@background)
    end

    def call
      unwrapped = unwrap_longitudes(@segments)
      unwrapped = smooth(unwrapped) if @smoothing
      svg_text = if @basemap
        basemap_svg(unwrapped, @basemap)
      else
        svg(simplify(project(unwrapped)))
      end
      svg_file = Tempfile.new([ "allure-route", ".svg" ], binmode: true)
      svg_file.write(svg_text)
      svg_file.rewind

      output = render_png(svg_file)
      output.rewind
      output
    rescue ArgumentError
      raise
    rescue StandardError => error
      raise RenderingError, "route image rendering failed", cause: error
    ensure
      svg_file&.close!
    end

    private

    def surface_colour = @background || SURFACE_COLOURS.fetch(@theme)
    def chevron_surface = CHEVRON_SURFACES.fetch(@theme)
    def dot_stroke = DOT_STROKES.fetch(@theme)

    # Requiring image_processing/vips blocks every untrusted libvips loader, SVG
    # included, for the whole process, because uploaded SVG is untrusted. This
    # SVG is generated entirely from validated numeric coordinates and colours,
    # so unlock only for the duration of this conversion and serialize access.
    def render_png(svg_file)
      SVG_RENDER_MUTEX.synchronize do
        Vips.block("VipsForeignLoadSvg", false)
        ImageProcessing::Vips
          .source(svg_file)
          .convert("png")
          .saver(strip: true)
          .call
      ensure
        Vips.block("VipsForeignLoadSvg", true)
      end
    end

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

    def unwrap_longitudes(segments)
      previous_longitude = nil
      previous_unwrapped = nil

      segments.map do |segment|
        segment.map do |longitude, latitude|
          unwrapped = if previous_longitude
            previous_unwrapped + Allure::Gpx::Geo.normalize_longitude_delta(longitude - previous_longitude)
          else
            longitude
          end
          previous_longitude = longitude
          previous_unwrapped = unwrapped
          [ unwrapped, latitude ]
        end
      end
    end

    def smooth(segments)
      segments.map { |segment| Allure::Geometry::Smoothing.smooth(segment, level: @smoothing) }
    end

    def project(segments)
      points = segments.flatten(1)
      mean_latitude = points.sum { it[1] } / points.length
      reference_longitude = points.first[0]
      latitude_radians = Allure::Gpx::Geo.to_radians(mean_latitude)
      longitude_scale = Math.cos(latitude_radians)

      segments.map do |segment|
        segment.map do |longitude, latitude|
          x = Allure::Gpx::Geo::EARTH_RADIUS_METRES *
              Allure::Gpx::Geo.to_radians(longitude - reference_longitude) * longitude_scale
          y = Allure::Gpx::Geo::EARTH_RADIUS_METRES * Allure::Gpx::Geo.to_radians(latitude - mean_latitude)
          [ x, y ]
        end
      end
    end

    def simplify(segments)
      minimum_points = segments.sum { [ it.length, 2 ].min }
      raise ArgumentError, "too many route segments to render" if minimum_points > MAX_POINTS
      return segments if segments.sum(&:length) <= MAX_POINTS

      tolerance = 1.0
      loop do
        simplified = segments.map { ramer_douglas_peucker(it, tolerance) }
        return simplified if simplified.sum(&:length) <= MAX_POINTS

        tolerance *= 2
        raise RenderingError, "route simplification did not converge" unless tolerance.finite?
      end
    end

    def ramer_douglas_peucker(points, tolerance)
      return points if points.length <= 2

      kept = Array.new(points.length, false)
      kept[0] = true
      kept[-1] = true
      ranges = [ [ 0, points.length - 1 ] ]

      until ranges.empty?
        first_index, last_index = ranges.pop
        farthest_index = nil
        farthest_distance = -1.0

        ((first_index + 1)...last_index).each do |index|
          distance = perpendicular_distance(points[index], points[first_index], points[last_index])
          if distance > farthest_distance
            farthest_distance = distance
            farthest_index = index
          end
        end
        next unless farthest_distance > tolerance

        kept[farthest_index] = true
        ranges << [ farthest_index, last_index ]
        ranges << [ first_index, farthest_index ]
      end

      points.each_index.filter_map { |index| points[index] if kept[index] }
    end

    def perpendicular_distance(point, line_start, line_end)
      delta_x = line_end[0] - line_start[0]
      delta_y = line_end[1] - line_start[1]
      length_squared = (delta_x**2) + (delta_y**2)
      return Math.hypot(point[0] - line_start[0], point[1] - line_start[1]) if length_squared.zero?

      ratio = (((point[0] - line_start[0]) * delta_x) + ((point[1] - line_start[1]) * delta_y)) / length_squared
      ratio = ratio.clamp(0.0, 1.0)
      projected_x = line_start[0] + (ratio * delta_x)
      projected_y = line_start[1] + (ratio * delta_y)
      Math.hypot(point[0] - projected_x, point[1] - projected_y)
    end

    def svg(segments)
      canvas_segments, scale = fit_to_canvas(segments)
      paths = track_paths(canvas_segments, closure: Allure::Geometry::LoopExterior::CLOSURE_METRES * scale)
      start_x, start_y = canvas_segments.first.first
      finish_x, finish_y = canvas_segments.last.last

      <<~SVG.delete("\n")
        <svg xmlns="http://www.w3.org/2000/svg" width="#{WIDTH}" height="#{HEIGHT}" viewBox="0 0 #{WIDTH} #{HEIGHT}">
          <rect width="#{WIDTH}" height="#{HEIGHT}" fill="#{surface_colour}"/>
          #{paths}
          #{endpoint_dots(start_x, start_y, finish_x, finish_y)}
        </svg>
      SVG
    end

    def track_paths(canvas_segments, closure:)
      polylines = canvas_segments.map do |segment|
        points = segment.map { |x, y| format("%.3f,%.3f", x, y) }.join(" ")
        %(<polyline points="#{points}" fill="none" stroke="#{@line_colour}" stroke-width="#{LINE_WIDTH}" stroke-linecap="round" stroke-linejoin="round"/>)
      end
      covered = {}
      chevrons = canvas_segments.flat_map { |segment| direction_chevrons(segment, covered, closure) }
      chevrons = [] if chevrons.length < MIN_DIRECTION_COUNT

      (polylines + chevrons).join
    end

    def direction_chevrons(segment, covered, closure)
      Allure::Geometry::DirectionChevrons.placements(segment, covered:, closure:).map do |placement|
        transform = "translate(#{format('%.3f', placement.x)} #{format('%.3f', placement.y)}) rotate(#{format('%.3f', placement.angle)}) translate(0 #{12 * placement.side})"
        halo = <<~PATH.delete("\n")
          <path d="#{CHEVRON_PATH}" fill="none" stroke="#{chevron_surface}" stroke-width="#{CHEVRON_HALO_WIDTH}" stroke-linejoin="round" stroke-linecap="round" transform="#{transform}"/>
        PATH
        core = <<~PATH.delete("\n")
          <path d="#{CHEVRON_PATH}" fill="none" stroke="#{@line_colour}" stroke-width="#{CHEVRON_CORE_WIDTH}" stroke-linejoin="round" stroke-linecap="round" transform="#{transform}"/>
        PATH

        halo + core
      end
    end

    def endpoint_dots(start_x, start_y, finish_x, finish_y)
      <<~DOTS.delete("\n")
        <circle cx="#{format('%.3f', start_x)}" cy="#{format('%.3f', start_y)}" r="#{DOT_RADIUS}" fill="#{START_COLOUR}" stroke="#{dot_stroke}" stroke-width="#{DOT_STROKE}"/>
        #{finish_dot(finish_x, finish_y)}
      DOTS
    end

    # Checkered-flag finish: a black/white pattern disc with the same surface
    # ring as the start, so the two endpoints stay distinguishable in print,
    # colour-blind readers and on any basemap.
    def finish_dot(finish_x, finish_y)
      half = CHECKER_SIZE / 2
      <<~DOT.delete("\n")
        <defs>
          <pattern id="finish-checker" width="#{CHECKER_SIZE}" height="#{CHECKER_SIZE}" patternUnits="userSpaceOnUse">
            <rect width="#{half}" height="#{half}" fill="#{FINISH_CHECKER_DARK}"/>
            <rect x="#{half}" y="#{half}" width="#{half}" height="#{half}" fill="#{FINISH_CHECKER_DARK}"/>
          </pattern>
        </defs>
        <circle cx="#{format('%.3f', finish_x)}" cy="#{format('%.3f', finish_y)}" r="#{FINISH_DOT_RADIUS}" fill="url(#finish-checker)"/>
        <circle cx="#{format('%.3f', finish_x)}" cy="#{format('%.3f', finish_y)}" r="#{FINISH_DOT_RADIUS}" fill="none" stroke="#{dot_stroke}" stroke-width="#{DOT_STROKE}"/>
      DOT
    end

    def attribution_text
      text = @attribution || ATTRIBUTION_TEXT
      %(<text x="#{WIDTH - 8}" y="#{HEIGHT - 10}" text-anchor="end" font-family="sans-serif" font-size="#{ATTRIBUTION_FONT_SIZE}" fill="#{ATTRIBUTION_FILLS.fetch(@theme)}" stroke="#{ATTRIBUTION_STROKES.fetch(@theme)}" stroke-width="6" paint-order="stroke">#{text}</text>)
    end

    # Basemap path: project into the fetcher's WebMercator pixel space so the
    # track aligns with the stitched tiles, scale both together onto the
    # canvas, and embed the resized raster as a data-uri image.
    def basemap_svg(unwrapped, basemap)
      zoom = Integer(basemap.zoom)
      x_min = Integer(basemap.x_min)
      y_min = Integer(basemap.y_min)
      stitched_bytes = basemap.png_bytes.to_s.b
      raise ArgumentError, "invalid route basemap" unless zoom.between?(0, 19) && x_min >= 0 && y_min >= 0
      raise ArgumentError, "invalid route basemap" if stitched_bytes.empty?

      pixel_segments = simplify_mercator(unwrapped, zoom)
      canvas_segments, scale, center = fit_mercator_to_canvas(pixel_segments)
      stitched = Vips::Image.new_from_buffer(stitched_bytes, "")
      stitch_width = stitched.width.to_f
      stitch_height = stitched.height.to_f
      raise ArgumentError, "invalid route basemap" unless stitch_width.positive? && stitch_height.positive?

      origin_x = x_min * RouteBasemapFetcher::TILE_SIZE
      origin_y = y_min * RouteBasemapFetcher::TILE_SIZE
      left = (WIDTH / 2.0) + ((origin_x - center[0]) * scale)
      top = (HEIGHT / 2.0) + ((origin_y - center[1]) * scale)
      placed_width = stitch_width * scale
      placed_height = stitch_height * scale
      resized_bytes = if scale == 1.0
        stitched_bytes
      else
        stitched.resize(scale).write_to_buffer(".png").b
      end
      encoded = Base64.strict_encode64(resized_bytes)
      image_tag = %(<image x="#{format('%.3f', left)}" y="#{format('%.3f', top)}" width="#{format('%.3f', placed_width)}" height="#{format('%.3f', placed_height)}" preserveAspectRatio="none" xlink:href="data:image/png;base64,#{encoded}" href="data:image/png;base64,#{encoded}"/>)

      latitude = unwrapped.flatten(1).sum { it[1] } / unwrapped.sum(&:length)
      circumference = 2 * Math::PI * Allure::Gpx::Geo::EARTH_RADIUS_METRES
      metres_per_pixel = circumference * Math.cos(Allure::Gpx::Geo.to_radians(latitude)) /
        (RouteBasemapFetcher::TILE_SIZE * (2**zoom))
      paths = track_paths(canvas_segments, closure: Allure::Geometry::LoopExterior::CLOSURE_METRES * scale / metres_per_pixel)
      start_x, start_y = canvas_segments.first.first
      finish_x, finish_y = canvas_segments.last.last

      <<~SVG.delete("\n")
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="#{WIDTH}" height="#{HEIGHT}" viewBox="0 0 #{WIDTH} #{HEIGHT}">
          <rect width="#{WIDTH}" height="#{HEIGHT}" fill="#{surface_colour}"/>
          #{image_tag}
          #{paths}
          #{endpoint_dots(start_x, start_y, finish_x, finish_y)}
          #{attribution_text}
        </svg>
      SVG
    end

    def mercator_pixels(segments, zoom)
      segments.map do |segment|
        segment.map do |longitude, latitude|
          [ RouteBasemapFetcher.longitude_to_global_x(longitude, zoom), RouteBasemapFetcher.latitude_to_global_y(latitude, zoom) ]
        end
      end
    end

    def simplify_mercator(segments, zoom)
      pixel_segments = mercator_pixels(segments, zoom)
      minimum_points = pixel_segments.sum { [ it.length, 2 ].min }
      raise ArgumentError, "too many route segments to render" if minimum_points > MAX_POINTS
      return pixel_segments if pixel_segments.sum(&:length) <= MAX_POINTS

      tolerance = 1.0
      loop do
        simplified = pixel_segments.map { ramer_douglas_peucker(it, tolerance) }
        return simplified if simplified.sum(&:length) <= MAX_POINTS

        tolerance *= 2
        raise RenderingError, "route simplification did not converge" unless tolerance.finite?
      end
    end

    # Same fit logic as `fit_to_canvas` but without the north-up inversion:
    # Mercator global y already grows southward like canvas y.
    def fit_mercator_to_canvas(pixel_segments)
      points = pixel_segments.flatten(1)
      min_x, max_x = points.map(&:first).minmax
      min_y, max_y = points.map(&:last).minmax
      route_width = max_x - min_x
      route_height = max_y - min_y
      available_width = WIDTH - (2 * PADDING)
      available_height = HEIGHT - (2 * PADDING)
      scales = []
      scales << available_width / route_width if route_width.positive?
      scales << available_height / route_height if route_height.positive?
      scale = scales.min || 1.0
      center_x = (min_x + max_x) / 2.0
      center_y = (min_y + max_y) / 2.0

      canvas = pixel_segments.map do |segment|
        segment.map do |x, y|
          [ (WIDTH / 2.0) + ((x - center_x) * scale), (HEIGHT / 2.0) + ((y - center_y) * scale) ]
        end
      end
      [ canvas, scale, [ center_x, center_y ] ]
    end

    def fit_to_canvas(segments)
      points = segments.flatten(1)
      min_x, max_x = points.map(&:first).minmax
      min_y, max_y = points.map(&:last).minmax
      route_width = max_x - min_x
      route_height = max_y - min_y
      available_width = WIDTH - (2 * PADDING)
      available_height = HEIGHT - (2 * PADDING)
      scales = []
      scales << available_width / route_width if route_width.positive?
      scales << available_height / route_height if route_height.positive?
      scale = scales.min || 1.0
      center_x = (min_x + max_x) / 2.0
      center_y = (min_y + max_y) / 2.0

      canvas = segments.map do |segment|
        segment.map do |x, y|
          [ (WIDTH / 2.0) + ((x - center_x) * scale), (HEIGHT / 2.0) - ((y - center_y) * scale) ]
        end
      end
      [ canvas, scale ]
    end
  end
end
