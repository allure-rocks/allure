# frozen_string_literal: true

require "nokogiri"
require "time"

module Allure
  module Tcx
    # Turns untrusted Garmin TCX XML into an `Allure::Gpx::Track` of immutable
    # values. Never saves anything and knows nothing about Active Record.
    #
    # Uses `Nokogiri::XML::Reader`, a forward-only pull parser, so the
    # `<Trackpoint>` limit can be enforced while reading instead of after
    # loading the whole document into memory. Parsing is non-networked: only
    # `ParseOptions::NONET` is set, and DTD loading/entity substitution are
    # left off so an external entity reference (XXE) is never resolved.
    #
    # TCX carries no recording-pause marker, so every positioned trackpoint in
    # document order flattens into a single recording segment; `<Lap>`
    # elements become file-recorded laps (see `Allure::Gpx::Lap`). A
    # trackpoint with a position but no timestamp is malformed (it cannot be
    # ordered).
    #
    # When no trackpoint carries a position (Garmin's indoor exports), the
    # file is imported as a positionless recording: every timed trackpoint is
    # kept with its heart rate, cadence, watts, cumulative `DistanceMeters`
    # and TPX `Speed` (PLAN_NO_GPS.md §3).
    class Parser
      DEFAULT_MAX_POINTS = Allure::Gpx::Parser::DEFAULT_MAX_POINTS

      # TCX `<Activity Sport>` to a catalog alias the detector resolves.
      # Sports outside this map emit no signal and fall back to the user's
      # selected sport rather than misdetecting.
      SPORT_ALIASES = {
        "Running" => "run",
        "Biking" => "ride",
        "Walking" => "walk",
        "Hiking" => "hike",
        "Swimming" => "swim"
      }.freeze

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
        LEAF_ELEMENTS = %w[
          Time LatitudeDegrees LongitudeDegrees AltitudeMeters Value Cadence Watts
          TotalTimeSeconds DistanceMeters MaximumSpeed Calories TriggerMethod Notes Name Speed
        ].freeze

        def initialize(max_points:)
          @max_points = max_points
          @root_validated = false
          @creator = nil
          @doc_description = nil
          @doc_calories = nil
          @activity_signals = []
          @in_activity = false
          @in_author = false
          @in_lap = false
          @cur_lap_start = nil
          @cur_lap_total_time = nil
          @cur_lap_distance = nil
          @cur_lap_max_speed = nil
          @cur_lap_avg_hr = nil
          @cur_lap_max_hr = nil
          @cur_lap_trigger = nil
          @lap_records = []
          @in_trackpoint = false
          @in_avg_hr = false
          @in_max_hr = false
          @in_hr = false
          @cur_time = nil
          @cur_lat = nil
          @cur_lon = nil
          @cur_ele = nil
          @cur_hr = nil
          @cur_cad = nil
          @cur_power = nil
          @cur_distance = nil
          @cur_speed = nil
          @positioned_points = []
          @timed_points = []
          @previous_time = nil
          @point_count = 0
          @segments = []
          @pending_leaf = nil
          @text_buffer = nil
        end

        def call(io)
          reader = Nokogiri::XML::Reader(Allure::Xml::SanitizedSource.new(io), nil, nil, SAFE_PARSE_OPTIONS)
          reader.each { |node| process(node) }
          raise Allure::Gpx::MalformedXmlError, reader.errors.join("; ") if reader.errors.any?
          # TCX marks no pauses, so the whole recording is one segment. A file
          # with a positioned segment stays positioned even if a few
          # trackpoints lacked a fix; one with none opens a positionless
          # segment from every timed point (PLAN_NO_GPS.md §3).
          if @positioned_points.length >= 2
            @segments << Allure::Gpx::Segment.new(points: @positioned_points)
          elsif @timed_points.length >= 2
            @segments << Allure::Gpx::Segment.new(points: @timed_points)
          end
          raise Allure::Gpx::NoTrackError, "no valid timed trackpoints found" if @segments.empty?

          last_point_time = @segments.last.points.last.time
          laps = finalize_laps(last_point_time)
          Allure::Gpx::Track.new(
            creator: @creator,
            name: nil,
            description: @doc_description,
            calories: @doc_calories,
            source_max_speed: laps.filter_map(&:max_speed).select(&:positive?).max,
            activity_signals: @activity_signals,
            segments: @segments,
            laps:
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
            raise Allure::Gpx::UnsupportedGpxError, "root element must be <TrainingCenterDatabase>" unless name == "TrainingCenterDatabase"

            @root_validated = true
            return
          end

          case name
          when "Activity"
            @in_activity = true
            append_sport_signal(node.attribute("Sport"))
          when "Author"
            @in_author = true
          when "Lap"
            @in_lap = true
            @cur_lap_start = parse_lap_time(node.attribute("StartTime"))
            @cur_lap_total_time = nil
            @cur_lap_distance = nil
            @cur_lap_max_speed = nil
            @cur_lap_avg_hr = nil
            @cur_lap_max_hr = nil
            @cur_lap_trigger = nil
          when "Trackpoint"
            start_trackpoint
          when "AverageHeartRateBpm"
            @in_avg_hr = true
          when "MaximumHeartRateBpm"
            @in_max_hr = true
          when "HeartRateBpm"
            @in_hr = true if @in_trackpoint
          when *LEAF_ELEMENTS
            @pending_leaf = name
            @text_buffer = +""
          end
        end

        def start_trackpoint
          @point_count += 1
          raise Allure::Gpx::TooManyPointsError, "more than #{@max_points} trackpoints" if @point_count > @max_points

          @in_trackpoint = true
          @cur_time = nil
          @cur_lat = nil
          @cur_lon = nil
          @cur_ele = nil
          @cur_hr = nil
          @cur_cad = nil
          @cur_power = nil
          @cur_distance = nil
          @cur_speed = nil
        end

        def finish_element(name)
          case name
          when "Activity" then @in_activity = false
          when "Author" then @in_author = false
          when "Lap" then finish_lap
          when "Trackpoint" then finish_trackpoint
          when "AverageHeartRateBpm" then @in_avg_hr = false
          when "MaximumHeartRateBpm" then @in_max_hr = false
          when "HeartRateBpm" then @in_hr = false
          when "Name" then @creator = @text_buffer.strip if @in_author && @creator.nil?
          when "Notes" then capture_activity_notes
          when "Time" then @cur_time = parse_time(@text_buffer) if @in_trackpoint
          when "LatitudeDegrees" then @cur_lat = parse_coordinate(@text_buffer, -90.0, 90.0, "latitude") if @in_trackpoint
          when "LongitudeDegrees" then @cur_lon = parse_coordinate(@text_buffer, -180.0, 180.0, "longitude") if @in_trackpoint
          when "AltitudeMeters" then @cur_ele = parse_optional_float(@text_buffer) if @in_trackpoint
          when "Value"
            @cur_lap_avg_hr = parse_positive_integer(@text_buffer) if @in_avg_hr && @in_lap
            @cur_lap_max_hr = parse_positive_integer(@text_buffer) if @in_max_hr && @in_lap
            @cur_hr = parse_positive_integer(@text_buffer) if @in_hr
          when "Cadence" then @cur_cad = parse_optional_integer(@text_buffer) if @in_trackpoint
          when "Watts" then @cur_power = parse_optional_integer(@text_buffer) if @in_trackpoint
          when "TotalTimeSeconds" then @cur_lap_total_time = parse_optional_float(@text_buffer) if @in_lap
          when "DistanceMeters"
            if @in_trackpoint
              @cur_distance = parse_non_negative_float(@text_buffer)
            elsif @in_lap
              @cur_lap_distance = parse_non_negative_float(@text_buffer)
            end
          when "Speed" then @cur_speed = parse_non_negative_float(@text_buffer) if @in_trackpoint
          when "MaximumSpeed" then @cur_lap_max_speed = parse_optional_float(@text_buffer) if @in_lap
          when "Calories" then @doc_calories = (@doc_calories || 0) + parse_optional_integer(@text_buffer).to_i if @in_lap
          when "TriggerMethod" then @cur_lap_trigger = @text_buffer.strip.downcase.presence if @in_lap
          end
          @pending_leaf = nil if LEAF_ELEMENTS.include?(name)
        end

        def append_sport_signal(sport)
          value = SPORT_ALIASES[sport.to_s.strip]
          return if value.nil? || value.empty?
          return if @activity_signals.length >= Allure::Gpx::Parser::MAX_ACTIVITY_SIGNALS

          @activity_signals << Allure::Gpx::ActivitySignal.new(source: :tcx_sport, value:)
        end

        def capture_activity_notes
          return unless @in_activity && !@in_lap && !@in_trackpoint
          return unless @doc_description.nil?

          stripped = @text_buffer.strip
          @doc_description = stripped unless stripped.empty?
        end

        def finish_lap
          @lap_records << {
            start: @cur_lap_start,
            total_time: @cur_lap_total_time,
            distance: @cur_lap_distance,
            max_speed: @cur_lap_max_speed,
            avg_hr: @cur_lap_avg_hr,
            max_hr: @cur_lap_max_hr,
            trigger: @cur_lap_trigger
          } if @in_activity
          @in_lap = false
          @cur_lap_start = nil
        end

        # A trackpoint before GPS lock (or on an indoor recording) has no
        # position: it keeps its readings and joins the timed stream instead.
        # The two groups are collected until the file's kind is known: a file
        # with two positioned points is positioned and keeps only those, so
        # the unpositioned portions stay skipped exactly as before.
        #
        # A positioned trackpoint without a timestamp is malformed, as ever. An
        # unpositioned one without a timestamp cannot be ordered and is
        # dropped, never fatal: the file still has to prove itself with two
        # timed points.
        def finish_trackpoint
          positioned = !@cur_lat.nil? && !@cur_lon.nil?

          if @cur_time.nil?
            raise Allure::Gpx::MissingTimestampError, "trackpoint has no timestamp" if positioned

            @in_trackpoint = false
            @in_hr = false
            return
          end
          raise Allure::Gpx::NonMonotonicTimestampError, "timestamps decreased" if @previous_time && @cur_time < @previous_time

          @previous_time = @cur_time
          point = Allure::Gpx::Point.new(
            time: @cur_time,
            latitude: @cur_lat,
            longitude: @cur_lon,
            elevation: @cur_ele,
            heart_rate: @cur_hr,
            cadence: @cur_cad,
            power: @cur_power,
            distance: @cur_distance,
            speed: @cur_speed
          )
          @positioned_points << point if positioned
          @timed_points << point
          @in_trackpoint = false
          @in_hr = false
        end

        # Lap ends are the next lap's start, or the last recorded point for
        # the final lap. `moving_time` equals elapsed: a TCX lap carries no
        # pause breakdown. A lap without a usable start is dropped, never
        # fatal — recorded laps are display-only.
        def finalize_laps(last_point_time)
          @lap_records.each_with_index.filter_map do |record, index|
            start = record[:start]
            next if start.nil?

            end_time = @lap_records[index + 1]&.dig(:start) || last_point_time
            next if end_time.nil? || end_time <= start

            elapsed = record[:total_time] ? record[:total_time].round : (end_time - start).round
            distance = record[:distance]
            average_speed = distance && elapsed.positive? ? distance / elapsed : nil
            Allure::Gpx::Lap.new(
              number: index + 1,
              started_at: start,
              elapsed_time: elapsed,
              moving_time: elapsed,
              distance:,
              average_speed:,
              max_speed: record[:max_speed],
              average_pace: distance && distance.positive? && elapsed.positive? ? (elapsed / (distance / 1000.0)).round : nil,
              average_heart_rate: record[:avg_hr],
              max_heart_rate: record[:max_hr],
              lap_trigger: record[:trigger]
            )
          end
        end

        def parse_coordinate(text, minimum, maximum, label)
          raise Allure::Gpx::InvalidPointError, "missing #{label}" if text.nil?

          value = Float(text.to_s.strip)
          raise Allure::Gpx::InvalidPointError, "malformed #{label}: #{text.inspect}" unless value.finite?
          raise Allure::Gpx::InvalidPointError, "#{label} out of range: #{text.inspect}" if value < minimum || value > maximum

          value
        rescue ArgumentError, TypeError
          raise Allure::Gpx::InvalidPointError, "malformed #{label}: #{text.inspect}"
        end

        def parse_time(text)
          stripped = text.to_s.strip
          return nil if stripped.empty?

          Time.iso8601(stripped)
        rescue ArgumentError, TypeError
          raise Allure::Gpx::InvalidPointError, "malformed timestamp: #{text.inspect}"
        end

        def parse_lap_time(text)
          stripped = text.to_s.strip
          return nil if stripped.empty?

          Time.iso8601(stripped)
        rescue ArgumentError, TypeError
          nil
        end

        def parse_optional_integer(text)
          stripped = text.to_s.strip
          return nil if stripped.empty?

          value = Float(stripped)
          return nil unless value.finite?

          value.round
        rescue ArgumentError, TypeError
          nil
        end

        # 0 bpm is a strap dropout, never a valid heart rate. Cadence/power
        # keep 0 (coasting) as valid.
        def parse_positive_integer(text)
          value = parse_optional_integer(text)
          value if value&.positive?
        end

        def parse_optional_float(text)
          stripped = text.to_s.strip
          return nil if stripped.empty?

          value = Float(stripped)
          value.finite? ? value : nil
        rescue ArgumentError, TypeError
          nil
        end

        # A device speed or distance: a negative reading is no reading.
        def parse_non_negative_float(text)
          value = parse_optional_float(text)
          value if value&.>= 0
        end
      end
      private_constant :Run
    end
  end
end
