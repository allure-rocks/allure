# frozen_string_literal: true

require "nokogiri"
require "time"

module Allure
  module Kml
    # Turns untrusted KML XML into an `Allure::Gpx::Track` of immutable
    # values. Never saves anything and knows nothing about Active Record.
    #
    # Uses `Nokogiri::XML::Reader`, a forward-only pull parser, so the
    # `<when>` and `<gx:coord>` limits are enforced while reading, before a
    # track's elements are paired, instead of after loading the whole
    # document into memory. Parsing is non-networked: only
    # `ParseOptions::NONET` is set, and DTD loading/entity substitution are
    # left off so an external entity reference (XXE) is never resolved.
    #
    # Only `gx:Track` elements with real `<when>` timestamps become points.
    # A plain `<LineString><coordinates>` carries no time, and fabricated
    # timestamps would poison durations, speeds, and records downstream — so
    # timeless geometry is ignored, and a file with no timed track raises
    # `NoTrackError`. KML has no lap concept; `Track#laps` is always empty.
    class Parser
      DEFAULT_MAX_POINTS = Allure::Gpx::Parser::DEFAULT_MAX_POINTS

      SAFE_PARSE_OPTIONS = Nokogiri::XML::ParseOptions::NONET

      def initialize(max_points: DEFAULT_MAX_POINTS)
        @max_points = max_points
      end

      def parse(io)
        Run.new(max_points: @max_points).call(io)
      end

      # Holds the mutable state for a single parse. Kept private to Parser so
      # a Parser instance itself stays reusable/stateless across calls.
      class Run
        LEAF_ELEMENTS = %w[name description when coord].freeze

        def initialize(max_points:)
          @max_points = max_points
          @root_validated = false
          @activity_signals = []
          @in_placemark = false
          @in_track = false
          @track_whens = []
          @track_coords = []
          @cur_segment_points = []
          @previous_time = nil
          @point_count = 0
          @when_count = 0
          @coord_count = 0
          @segments = []
          @pending_leaf = nil
          @text_buffer = nil
        end

        def call(io)
          reader = Nokogiri::XML::Reader(Allure::Xml::SanitizedSource.new(io), nil, nil, SAFE_PARSE_OPTIONS)
          reader.each { |node| process(node) }
          raise Allure::Gpx::MalformedXmlError, reader.errors.join("; ") if reader.errors.any?
          raise Allure::Gpx::NoTrackError, "no timed gx:Track found" if @cur_segment_points.length < 2

          @segments << Allure::Gpx::Segment.new(points: @cur_segment_points)

          Allure::Gpx::Track.new(
            creator: nil,
            name: nil,
            description: nil,
            calories: nil,
            activity_signals: @activity_signals,
            segments: @segments,
            laps: []
          )
        rescue Nokogiri::XML::SyntaxError => e
          raise Allure::Gpx::MalformedXmlError, e.message
        end

        private

        def process(node)
          case node.node_type
          when Nokogiri::XML::Reader::TYPE_ELEMENT
            start_element(node)
            finish_element(node.local_name) if node.self_closing?
          when Nokogiri::XML::Reader::TYPE_TEXT, Nokogiri::XML::Reader::TYPE_CDATA
            @text_buffer << node.value if @pending_leaf
          when Nokogiri::XML::Reader::TYPE_END_ELEMENT
            finish_element(node.local_name)
          end
        end

        def start_element(node)
          name = node.local_name

          unless @root_validated
            raise Allure::Gpx::UnsupportedGpxError, "root element must be <kml>" unless name == "kml"

            @root_validated = true
            return
          end

          case name
          when "Placemark"
            @in_placemark = true
          when "Track"
            @in_track = true
            @track_whens = []
            @track_coords = []
          when *LEAF_ELEMENTS
            @pending_leaf = name
            @text_buffer = +""
          end
        end

        def finish_element(name)
          case name
          when "Placemark" then @in_placemark = false
          when "Track" then finish_track
          when "name" then append_signal(:kml_name) if @in_placemark
          when "description" then append_signal(:kml_description) if @in_placemark
          when "when" then keep_when if @in_track
          when "coord" then keep_coord if @in_track
          end
          @pending_leaf = nil if LEAF_ELEMENTS.include?(name)
        end

        # Counted over the whole file: a valid point needs one of each, so
        # past `max_points` of either no file can stay under the point cap,
        # and an unreadable element is never kept beyond it.
        def keep_when
          @when_count += 1
          raise Allure::Gpx::TooManyPointsError, "more than #{@max_points} when elements" if @when_count > @max_points

          @track_whens << @text_buffer.dup
        end

        def keep_coord
          @coord_count += 1
          raise Allure::Gpx::TooManyPointsError, "more than #{@max_points} coord elements" if @coord_count > @max_points

          @track_coords << @text_buffer.dup
        end

        def append_signal(source)
          value = @text_buffer.to_s.strip
          return if value.empty? || @activity_signals.length >= Allure::Gpx::Parser::MAX_ACTIVITY_SIGNALS

          @activity_signals << Allure::Gpx::ActivitySignal.new(source:, value:)
        end

        # Pairs `<when>` timestamps with `<gx:coord>` positions by index. A
        # malformed pair is skipped (best-effort on extension structure); a
        # track yielding fewer than two valid points contributes nothing.
        def finish_track
          @in_track = false
          pairs = @track_whens.zip(@track_coords)
          pairs.each do |when_text, coord_text|
            time = parse_time(when_text)
            next if time.nil?

            coordinate = parse_coord(coord_text)
            next if coordinate.nil?

            if @previous_time && time < @previous_time
              raise Allure::Gpx::NonMonotonicTimestampError, "timestamps decreased"
            end

            @point_count += 1
            raise Allure::Gpx::TooManyPointsError, "more than #{@max_points} coordinates" if @point_count > @max_points

            @previous_time = time
            longitude, latitude, elevation = coordinate
            @cur_segment_points << Allure::Gpx::Point.new(
              time:, latitude:, longitude:, elevation:
            )
          end
          @track_whens = []
          @track_coords = []
        end

        def parse_time(text)
          stripped = text.to_s.strip
          return nil if stripped.empty?

          Time.iso8601(stripped)
        rescue ArgumentError, TypeError
          nil
        end

        def parse_coord(text)
          parts = text.to_s.strip.split(/\s+/)
          return nil if parts.length < 2

          longitude = Float(parts[0])
          latitude = Float(parts[1])
          return nil unless longitude.finite? && latitude.finite?
          return nil unless longitude.between?(-180, 180) && latitude.between?(-90, 90)

          elevation = parts[2] ? Float(parts[2]) : nil
          elevation = nil unless elevation&.finite?

          [ longitude, latitude, elevation ]
        rescue ArgumentError, TypeError
          raise Allure::Gpx::InvalidPointError, "malformed coordinate: #{text.inspect}"
        end
      end
      private_constant :Run
    end
  end
end
