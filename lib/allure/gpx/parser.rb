# frozen_string_literal: true

require "nokogiri"
require "time"

module Allure
  module Gpx
    # Turns untrusted GPX XML into an `Allure::Gpx::Track` of immutable
    # values. Never saves anything and knows nothing about Active Record.
    #
    # Uses `Nokogiri::XML::Reader`, a forward-only pull parser, so the
    # `<trkpt>` limit can be enforced while reading instead of after loading
    # the whole document into memory (see PLAN_M1.md section 7.1). Parsing is
    # non-networked: only `ParseOptions::NONET` is set, and DTD loading/entity
    # substitution are left off so an external entity reference (XXE) is
    # never resolved and never fetched over the network.
    class Parser
      # The cap bounds the analyzer's linear work, not a product rule: a long
      # ultra can legitimately carry >100k points in a 25 MB upload.
      DEFAULT_MAX_POINTS = 250_000
      # Signals only hint at the sport and the first ones carry it; a file
      # repeating a hinting element millions of times keeps no more than
      # this, shared by the GPX, TCX and KML parsers.
      MAX_ACTIVITY_SIGNALS = 32
      SUPPORTED_NAMESPACES = [
        "http://www.topografix.com/GPX/1/0",
        "http://www.topografix.com/GPX/1/1"
      ].freeze
      SUPPORTED_VERSIONS = %w[1.0 1.1].freeze
      SAFE_PARSE_OPTIONS = Nokogiri::XML::ParseOptions::NONET

      def initialize(max_points: DEFAULT_MAX_POINTS, require_timestamps: true)
        @max_points = max_points
        @require_timestamps = require_timestamps
      end

      def parse(io)
        Run.new(max_points: @max_points, require_timestamps: @require_timestamps).call(io)
      end

      # Holds the mutable state for a single parse. Kept private to Parser so
      # a Parser instance itself stays reusable/stateless across calls.
      class Run
        LEAF_ELEMENTS = %w[
          name desc type keywords activity route cal calories ele time dist hr cad power powerinwatts atemp
        ].freeze
        OSMAND_NAMESPACE = "https://osmand.net/docs/technical/osmand-file-formats/osmand-gpx"

        def initialize(max_points:, require_timestamps: true)
          @max_points = max_points
          @require_timestamps = require_timestamps
          @root_validated = false
          @creator = nil
          @doc_name = nil
          @doc_description = nil
          @doc_calories = nil
          @activity_signals = []
          @in_metadata = false
          @in_metadata_extensions = false
          @in_root_extensions = false
          @in_trk = false
          @in_trk_extensions = false
          @in_trkpt = false
          @in_lap = false
          @cur_lap_time = nil
          @cur_lap_distance = nil
          @cur_trk_name = nil
          @cur_trk_description = nil
          @cur_trk_calories = nil
          @cur_segment_points = nil
          @previous_time_in_segment = nil
          @point_count = 0
          @segments = []
          @lap_records = []
          @pending_leaf = nil
          @pending_leaf_namespace = nil
          @text_buffer = nil
        end

        def call(io)
          reader = Nokogiri::XML::Reader(Allure::Xml::SanitizedSource.new(io), nil, nil, SAFE_PARSE_OPTIONS)
          reader.each { |node| process(node) }
          raise MalformedXmlError, reader.errors.join("; ") if reader.errors.any?
          raise NoTrackError, "no valid track segments found" if @segments.empty?

          Track.new(
            creator: @creator,
            name: @doc_name,
            description: @doc_description,
            calories: @doc_calories,
            activity_signals: @activity_signals,
            segments: @segments,
            laps: finalize_laps
          )
        rescue Nokogiri::XML::SyntaxError => e
          raise MalformedXmlError, e.message
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
            validate_root!(node)
            @creator = node.attribute("creator")
            @root_validated = true
            return
          end

          case name
          when "metadata"
            @in_metadata = true
          when "trk"
            @in_trk = true
            @cur_trk_name = nil
            @cur_trk_description = nil
            @cur_trk_calories = nil
          when "extensions"
            if @in_metadata
              @in_metadata_extensions = true
            elsif @in_trk && !@cur_segment_points
              @in_trk_extensions = true
            elsif !@in_trk
              @in_root_extensions = true
            end
          when "trkseg"
            @cur_segment_points = []
            @previous_time_in_segment = nil
          when "trkpt"
            start_point(node)
          when "lap"
            @in_lap = true
            @cur_lap_time = nil
            @cur_lap_distance = nil
          when *LEAF_ELEMENTS
            @pending_leaf = name.downcase
            @pending_leaf_namespace = node.namespace_uri
            @text_buffer = +""
          end
        end

        def start_point(node)
          @point_count += 1
          raise TooManyPointsError, "more than #{@max_points} trkpt elements" if @point_count > @max_points

          @in_trkpt = true
          @cur_lat = parse_coordinate(node.attribute("lat"), -90.0, 90.0, "latitude")
          @cur_lon = parse_coordinate(node.attribute("lon"), -180.0, 180.0, "longitude")
          @cur_ele = nil
          @cur_time = nil
          @cur_hr = nil
          @cur_cad = nil
          @cur_power = nil
          @cur_temperature = nil
        end

        def finish_element(name)
          case name
          when "metadata" then @in_metadata = false
          when "trk" then finish_trk
          when "extensions"
            @in_trk_extensions = false
            @in_metadata_extensions = false
            @in_root_extensions = false
          when "trkseg" then finish_trkseg
          when "trkpt" then finish_trkpt
          when "lap" then finish_lap
          when "name"
            if @in_trk && !@in_trkpt && !@in_lap
              @cur_trk_name = @text_buffer
            elsif @in_metadata && !@in_trkpt && supported_namespace?(@pending_leaf_namespace)
              append_activity_signal(:gpx_metadata_name)
            end
          when "desc"
            if @in_trk && !@in_trkpt
              @cur_trk_description = @text_buffer
            elsif @in_metadata && !@in_trkpt && supported_namespace?(@pending_leaf_namespace)
              append_activity_signal(:gpx_metadata_description)
            end
          when "type" then capture_track_type
          when "keywords" then capture_metadata_keywords
          when "activity" then capture_osmand_activity
          when "route" then capture_osmand_route
          when "cal", "calories" then @cur_trk_calories = parse_optional_integer(@text_buffer) if @in_trk_extensions
          when "ele" then @cur_ele = parse_elevation(@text_buffer) if @in_trkpt
          when "time"
            if @in_trkpt
              @cur_time = parse_time(@text_buffer)
            elsif @in_lap
              @cur_lap_time = parse_lap_time(@text_buffer)
            end
          when "dist" then @cur_lap_distance = parse_optional_float(@text_buffer) if @in_lap
          when "hr" then @cur_hr = parse_positive_integer(@text_buffer) if @in_trkpt
          when "cad" then @cur_cad = parse_optional_integer(@text_buffer) if @in_trkpt
          when "power", "powerinwatts" then @cur_power = parse_optional_integer(@text_buffer) if @in_trkpt
          when "atemp" then @cur_temperature = parse_temperature(@text_buffer) if @in_trkpt
          end
          if LEAF_ELEMENTS.include?(name)
            @pending_leaf = nil
            @pending_leaf_namespace = nil
          end
        end

        def capture_track_type
          return unless @in_trk && !@in_trkpt
          return unless supported_namespace?(@pending_leaf_namespace)

          append_activity_signal(:gpx_track_type)
        end

        def capture_metadata_keywords
          return unless @in_metadata && !@in_trkpt
          return unless supported_namespace?(@pending_leaf_namespace)

          append_activity_signal(:gpx_keywords)
        end

        def capture_osmand_activity
          return unless @in_metadata_extensions
          return unless @pending_leaf_namespace == OSMAND_NAMESPACE

          append_activity_signal(:osmand_activity)
        end

        def capture_osmand_route
          return unless @in_root_extensions
          return unless @pending_leaf_namespace == OSMAND_NAMESPACE

          append_activity_signal(:osmand_route)
        end

        def append_activity_signal(source)
          value = @text_buffer.to_s.strip
          return if value.empty? || @activity_signals.length >= Parser::MAX_ACTIVITY_SIGNALS

          @activity_signals << ActivitySignal.new(source:, value:)
        end

        def supported_namespace?(namespace_uri)
          Parser::SUPPORTED_NAMESPACES.include?(namespace_uri)
        end

        def finish_trk
          if @doc_name.nil? && @cur_trk_name
            stripped = @cur_trk_name.strip
            @doc_name = stripped unless stripped.empty?
          end
          if @doc_description.nil? && @cur_trk_description
            stripped = @cur_trk_description.strip
            @doc_description = stripped unless stripped.empty?
          end
          @doc_calories = (@doc_calories || 0) + @cur_trk_calories if @cur_trk_calories
          @in_trk = false
        end

        def finish_trkseg
          points = ElevationPlaceholders.resolve(@cur_segment_points)
          @segments << Segment.new(points:) if points.length >= 2
          @cur_segment_points = nil
        end

        def finish_trkpt
          if @cur_time.nil?
            raise MissingTimestampError, "trkpt has no timestamp" if @require_timestamps
          elsif @previous_time_in_segment && @cur_time < @previous_time_in_segment
            raise NonMonotonicTimestampError, "timestamps decreased within a segment"
          end

          @previous_time_in_segment = @cur_time unless @cur_time.nil?
          @cur_segment_points << Point.new(
            time: @cur_time,
            latitude: @cur_lat,
            longitude: @cur_lon,
            elevation: @cur_ele,
            heart_rate: @cur_hr,
            cadence: @cur_cad,
            power: @cur_power,
            temperature: @cur_temperature
          )
          @in_trkpt = false
        end

        # Only laps attached to the recorded track count; a lap in `<metadata>`
        # is a summary, not a recorded boundary, and is ignored.
        def finish_lap
          @lap_records << { time: @cur_lap_time, distance: @cur_lap_distance } if @in_trk
          @in_lap = false
          @cur_lap_time = nil
          @cur_lap_distance = nil
        end

        # Laps are bounded by their `<time>` values, read as lap *start* times,
        # and by the last recorded point for the final lap. `moving_time` is set
        # to `elapsed_time`: a GPX `<lap>` carries no pause breakdown, so all
        # elapsed time is treated as moving. A lap whose start or the following
        # boundary is missing or non-monotonic is dropped, never rejected —
        # recorded laps are display-only, so a malformed lap must not fail an
        # otherwise valid import.
        def finalize_laps
          return [] if @lap_records.empty?

          last_point_time = @segments.last.points.last.time
          @lap_records.each_with_index.filter_map do |record, index|
            start = record[:time]
            next if start.nil?

            end_time = @lap_records[index + 1]&.dig(:time) || last_point_time
            next if end_time.nil? || end_time <= start

            elapsed = (end_time - start).round
            distance = record[:distance]
            average_speed = distance && elapsed.positive? ? distance / elapsed : nil
            Lap.new(
              number: index + 1,
              started_at: start,
              elapsed_time: elapsed,
              moving_time: elapsed,
              distance:,
              average_speed:,
              average_pace: distance && distance.positive? && elapsed.positive? ? (elapsed / (distance / 1000.0)).round : nil
            )
          end
        end

        def validate_root!(node)
          raise UnsupportedGpxError, "root element must be <gpx>" unless node.local_name == "gpx"
          raise UnsupportedGpxError, "unsupported GPX namespace: #{node.namespace_uri.inspect}" unless
            SUPPORTED_NAMESPACES.include?(node.namespace_uri)

          version = node.attribute("version")
          raise UnsupportedGpxError, "unsupported GPX version: #{version.inspect}" unless
            SUPPORTED_VERSIONS.include?(version)
        end

        def parse_coordinate(text, minimum, maximum, label)
          raise InvalidPointError, "missing #{label}" if text.nil?

          value = Float(text)
          raise InvalidPointError, "malformed #{label}: #{text.inspect}" unless value.finite?
          raise InvalidPointError, "#{label} out of range: #{text.inspect}" if value < minimum || value > maximum

          value
        rescue ArgumentError, TypeError
          raise InvalidPointError, "malformed #{label}: #{text.inspect}"
        end

        def parse_elevation(text)
          stripped = text.to_s.strip
          return nil if stripped.empty?

          value = Float(stripped)
          raise InvalidPointError, "malformed elevation: #{text.inspect}" unless value.finite?

          value
        rescue ArgumentError, TypeError
          raise InvalidPointError, "malformed elevation: #{text.inspect}"
        end

        def parse_time(text)
          stripped = text.to_s.strip
          return nil if stripped.empty?

          Time.iso8601(stripped)
        rescue ArgumentError, TypeError
          raise InvalidPointError, "malformed timestamp: #{text.inspect}"
        end

        # Lenient variant for a `<lap>` time: a malformed value yields nil (the
        # lap is dropped) rather than raising, unlike a trkpt timestamp, which
        # is mandatory for a valid import.
        def parse_lap_time(text)
          stripped = text.to_s.strip
          return nil if stripped.empty?

          Time.iso8601(stripped)
        rescue ArgumentError, TypeError
          nil
        end

        # Optional extension values (hr/cad/power/calories) are lenient: a
        # malformed value is ignored and omitted rather than rejecting an
        # otherwise valid import.
        def parse_optional_integer(text)
          stripped = text.to_s.strip
          return nil if stripped.empty?

          value = Float(stripped)
          return nil unless value.finite?

          value.round
        rescue ArgumentError, TypeError
          nil
        end

        # Heart rate is the exception: 0 bpm is physiologically impossible
        # and devices emit it for strap dropouts, so a non-positive value
        # is treated as missing rather than preserved. Cadence/power keep
        # 0 (coasting) as valid.
        def parse_positive_integer(text)
          value = parse_optional_integer(text)
          value if value&.positive?
        end

        # The Garmin `atemp` air temperature (°C), dropped when implausible.
        def parse_temperature(text)
          value = parse_optional_float(text)
          value if value && Point::TEMPERATURE_RANGE.cover?(value)
        end

        # Lenient float for a `<lap><dist>`: a malformed value is ignored and
        # the lap keeps a nil distance rather than rejecting the import.
        def parse_optional_float(text)
          stripped = text.to_s.strip
          return nil if stripped.empty?

          value = Float(stripped)
          value.finite? ? value : nil
        rescue ArgumentError, TypeError
          nil
        end
      end
      private_constant :Run
    end
  end
end
