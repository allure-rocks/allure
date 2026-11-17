# frozen_string_literal: true

module Allure
  module Fit
    # Turns a FIT activity file into an `Allure::Gpx::Track` of immutable
    # values, the same contract `Allure::Gpx::Parser` produces. Everything
    # downstream — the analyzer, point serializer, chart and track series,
    # splits, route image, segment matching and publishing — therefore works
    # on a FIT import with no change. See docs/dev/FIT.md for why the
    # shared value objects keep their `Gpx` name.
    #
    # Never saves anything and knows nothing about Active Record.
    class Parser
      # Shared with the GPX parser so one limit governs every import format.
      DEFAULT_MAX_POINTS = Allure::Gpx::Parser::DEFAULT_MAX_POINTS

      # FIT timestamps count seconds from 1989-12-31T00:00:00Z.
      EPOCH_OFFSET = 631_065_600
      # Below this, a FIT date_time is device uptime rather than UTC and
      # carries no usable wall-clock meaning.
      MIN_UTC_TIMESTAMP = 0x1000_0000
      # Real devices occasionally emit an isolated record whose clock glitched
      # backwards (the conformance corpus has both -1 s pairs and one bogus
      # multi-year jump). Those records are dropped instead of rejecting the
      # whole activity. A jump beyond CLOCK_RESET_THRESHOLD, or a longer
      # unbroken backward run, is a clock correction: the records from the
      # earlier epoch are discarded and the parser continues from the
      # corrected clock.
      MAX_BACKWARD_RECORDS = 5
      # One hour. Real jitter is seconds; a correction that moves the clock by
      # more than this is the device settling on the true time.
      CLOCK_RESET_THRESHOLD = 3600
      # A file is positioned when most of its timed records carry a fix. A
      # handful of stray fixes in an indoor recording (a brief lock by a
      # window, one decoded sentinel) would otherwise turn it into a
      # meaningless two-point track and discard every other reading
      # (docs/dev/NO-GPS.md).
      POSITIONED_RECORDS_RATIO = 0.5
      # Some devices (Suunto, COROS) write a record every second but a fix
      # only every few seconds, so a fully tracked outdoor file can fall under
      # the record ratio. It is positioned too when fixes are spread across
      # most of the recording: at least this share of the minutes that hold a
      # record also hold a fix. A brief lock covers only a minute or two.
      POSITIONED_COVERAGE_RATIO = 0.5
      COVERAGE_WINDOW_SECONDS = 60

      SEMICIRCLES_TO_DEGREES = 180.0 / (2**31)
      # Altitude is stored as (metres + 500) * 5. Subtracting the offset in
      # raw units before dividing keeps representable values exact; dividing
      # first turns -12.4 m into -12.399999999999977.
      ALTITUDE_SCALE = 5.0
      ALTITUDE_RAW_OFFSET = 2500

      def initialize(max_points: DEFAULT_MAX_POINTS, decoder: Decoder.new)
        @max_points = max_points
        @decoder = decoder
      end

      def parse(io)
        Run.new(max_points: @max_points, decoder: @decoder).call(io)
      end

      # Holds the mutable state for a single parse, keeping Parser itself
      # reusable across calls, as the GPX parser does.
      class Run
        def initialize(max_points:, decoder:)
          @max_points = max_points
          @decoder = decoder
          @file_types = []
          @file_id = nil
          @session = nil
          @device_info = nil
          @records = []
          @stop_marks = []
          @laps = []
          @previous_time = nil
          @backward_records = 0
          @point_count = 0
        end

        def call(io)
          @decoder.decode(io) { |message| consume(message) }

          validate_file_type!

          segments = build_segments
          raise Allure::Gpx::NoTrackError, "no valid timed records found" if segments.empty?

          segments = calibrate_virtual_distance(segments)

          Allure::Gpx::Track.new(
            creator: creator,
            name: nil,
            description: nil,
            calories: @session&.dig(:total_calories),
            source_max_speed: source_max_speed,
            source_ascent: source_ascent,
            source_descent: source_descent,
            activity_signals: activity_signals,
            segments: segments,
            laps: @laps,
            commute_hint: commute_hint
          )
        end

        private

        def consume(message)
          case message.name
          when :file_id then consume_file_id(message.fields)
          when :session then @session ||= message.fields
          when :device_info then @device_info ||= message.fields
          when :record then consume_record(message.fields)
          when :event then consume_event(message.fields)
          when :lap then consume_lap(message.fields)
          end
        end

        def consume_file_id(fields)
          type = Profile.file_type(fields[:type]) || :unknown
          @file_types << type
          # A chained export may place a device or settings file before the
          # activity, so the activity's own file_id is the one that names the
          # creator.
          @file_id ||= fields if type == :activity
        end

        # Only Activity files describe a recorded effort. Importing a course
        # or workout file would fabricate an activity that never happened.
        # `file_id` is mandatory in the specification and every real encoder
        # emits it, so its absence cannot be used to bypass this check.
        def validate_file_type!
          raise UnsupportedFitError, "FIT file has no file_id message" if @file_types.empty?
          return if @file_types.include?(:activity)

          raise UnsupportedFitError, "unsupported FIT file type: #{@file_types.first}"
        end

        def consume_record(fields)
          time = decode_time(fields[:timestamp])
          return if time.nil?

          # The coordinates are optional: a record before GPS lock or during
          # an indoor portion keeps its sensor readings without them, and the
          # file is positionless when too few records ever carry a fix
          # (docs/dev/NO-GPS.md). A half-written fix is no fix.
          latitude = decode_coordinate(fields[:position_lat], -90.0, 90.0, "latitude")
          longitude = decode_coordinate(fields[:position_long], -180.0, 180.0, "longitude")
          latitude = longitude = nil unless latitude && longitude

          @point_count += 1
          raise Allure::Gpx::TooManyPointsError, "more than #{@max_points} records" if @point_count > @max_points

          if @previous_time && time < @previous_time
            @backward_records += 1
            jump = @previous_time - time
            # A large jump, or an unbroken backward run, is a clock correction
            # rather than jitter: the device (or its GPS) reset the clock and
            # every later record uses the true time. Discard the records
            # recorded before the correction and continue from this one.
            if jump > CLOCK_RESET_THRESHOLD || @backward_records > MAX_BACKWARD_RECORDS
              @records.clear
              @stop_marks.clear
              @backward_records = 0
            else
              return
            end
          else
            @backward_records = 0
          end

          @previous_time = time
          @records << Allure::Gpx::Point.new(
            time:,
            latitude:,
            longitude:,
            elevation: decode_altitude(fields),
            heart_rate: positive_heart_rate(fields[:heart_rate]),
            cadence: fields[:cadence],
            power: fields[:power],
            speed: record_speed(fields),
            distance: record_distance(fields),
            temperature: record_temperature(fields)
          )
        end

        # The device's air-temperature reading (sint8, °C); an implausible
        # value is a sensor fault and is dropped.
        def record_temperature(fields)
          value = fields[:temperature]
          value if value.is_a?(Integer) && Allure::Gpx::Point::TEMPERATURE_RANGE.cover?(value)
        end

        # The device's cumulative distance, in metres. It is the distance
        # source of a positionless recording and never replaces the geodesic
        # measurement of a positioned one.
        def record_distance(fields)
          value = scaled(fields[:distance], 100.0)
          value if value&.finite? && value >= 0
        end

        # The device's own speed, in m/s. Most GNSS watches derive it from the
        # Doppler shift, far steadier than differentiating positions; on a
        # positioned recording it only arbitrates anomalies, never a metric
        # (docs/dev/WORKOUT.md), while a positionless one measures its movement
        # with it (docs/dev/NO-GPS.md).
        def record_speed(fields)
          value = scaled_speed(fields[:enhanced_speed] || fields[:speed])
          value if value&.finite? && value >= 0
        end

        # FIT has no `<trkseg>`. A recording segment ends where the timer was
        # stopped for the whole activity, matching FitTrackee's default.
        def consume_event(fields)
          return unless Profile.event(fields[:event]) == :timer
          return unless Profile.event_type(fields[:event_type]) == :stop_all

          time = decode_time(fields[:timestamp])
          @stop_marks << time if time
        end

        # A `lap` message carries values for that lap. The timestamp is when
        # the lap completed, so
        # `started_at` is the completion time minus the per-lap elapsed time. A
        # lap without a usable timestamp is dropped, never a fatal error.
        def consume_lap(fields)
          time = decode_time(fields[:timestamp])
          return if time.nil?

          elapsed = scaled(fields[:total_elapsed_time] || fields[:total_timer_time], 1000.0)
          moving = scaled(fields[:total_moving_time] || fields[:total_timer_time], 1000.0)
          elapsed = elapsed&.round
          moving = moving&.round
          moving = elapsed if moving && elapsed && moving > elapsed
          distance = scaled(fields[:total_distance], 100.0)
          ascent = fields[:total_ascent]
          descent = fields[:total_descent]

          average_speed = computed_average_speed(distance, moving) ||
            scaled_speed(fields[:enhanced_avg_speed] || fields[:avg_speed])

          @laps << Allure::Gpx::Lap.new(
            number: lap_number(fields[:message_index]),
            started_at: elapsed ? time - elapsed : time,
            elapsed_time: elapsed || 0,
            moving_time: moving || 0,
            distance:,
            ascent:,
            descent:,
            average_speed:,
            max_speed: scaled_speed(fields[:enhanced_max_speed] || fields[:max_speed]),
            average_pace: pace_for(average_speed),
            average_heart_rate: positive_heart_rate(fields[:avg_heart_rate]),
            max_heart_rate: positive_heart_rate(fields[:max_heart_rate]),
            average_cadence: fields[:avg_cadence],
            average_power: fields[:avg_power],
            lap_trigger: Profile.lap_trigger(fields[:lap_trigger])&.to_s
          )
        end

        def scaled_speed(value)
          scaled(value, 1000.0)
        end

        def scaled(value, scale)
          value && (value / scale)
        end

        def source_max_speed
          session_speed = [ @session&.dig(:enhanced_max_speed), @session&.dig(:max_speed) ]
            .filter_map { |value| scaled_speed(value) }
            .find(&:positive?)
          lap_speed = @laps.filter_map(&:max_speed).select(&:positive?).max
          session_speed || lap_speed
        end

        # The device's own elevation totals, when its session message carries
        # them. Validity and the lap fallback are `DeviceElevationTotals`' job.
        def source_ascent
          value = @session&.dig(:total_ascent)
          value if value.is_a?(Numeric)
        end

        def source_descent
          value = @session&.dig(:total_descent)
          value if value.is_a?(Numeric)
        end

        # The file's message_index is authoritative when it is usable: it keeps
        # the device's own numbering (and its gaps). Some devices reuse the same
        # index for every lap of an interval session, which would violate the
        # per-workout uniqueness of `laps.number`; a colliding index falls back
        # to the next free number so the laps still persist in order.
        def lap_number(message_index)
          if message_index
            candidate = (message_index & 0x0FFF) + 1
            return candidate if @laps.none? { |lap| lap.number == candidate }
          end

          (@laps.map(&:number).max || 0) + 1
        end

        def computed_average_speed(distance, moving)
          return nil unless distance && distance.positive? && moving && moving.positive?

          distance / moving
        end

        def pace_for(speed)
          return nil if speed.nil? || !speed.positive?

          (1000.0 / speed).round
        end

        # Records keep file order so a genuinely decreasing timestamp is still
        # an error; only the stop marks are placed by timestamp, because some
        # devices write every event after every record.
        #
        # A file with a usable fix opens positioned segments from its
        # positioned records, exactly as before. A file with no usable fix at
        # all (an indoor activity) opens positionless segments from every
        # timed record, so its heart rate, power and device distance are
        # analysed instead of discarded. Only a file with fewer than two timed
        # records is rejected (docs/dev/NO-GPS.md).
        def build_segments
          positioned = positioned_records
          if positioned
            return split_segments(positioned, marks: segment_marks(positioned)) do |segments, points|
              close_segment(segments, points)
            end
          end

          # A file that never reached a usable fix is positionless: its
          # records are kept, but a stray fix is stripped so no segment ever
          # mixes coordinates with positionless points (docs/dev/NO-GPS.md).
          split_segments(@records) do |segments, points|
            points = points.map { |point| point.positioned? ? point.with(latitude: nil, longitude: nil) : point }
            segments << Allure::Gpx::Segment.new(points:) if points.length >= 2
          end
        end

        # A virtual platform may draw the athlete somewhere else without moving
        # them (docs/dev/VIRTUAL-PLATFORMS.md). Those jumps close the recording segment
        # like a timer stop, so no line crosses the map and no speed is
        # measured across them. An ordinary device keeps its timer stops only.
        def segment_marks(points)
          return @stop_marks unless Allure::Virtual::Platforms.for_file_id(@file_id)

          (@stop_marks + Allure::Virtual::Teleports.marks(points)).uniq
        end

        def positioned_records
          positioned = @records.select(&:positioned?)
          return nil if positioned.length < 2
          return positioned if positioned.length >= POSITIONED_RECORDS_RATIO * @records.length
          return positioned if fix_coverage(positioned) >= POSITIONED_COVERAGE_RATIO

          nil
        end

        def fix_coverage(positioned)
          origin = @records.first.time
          minutes = ->(records) { records.map { |record| ((record.time - origin) / COVERAGE_WINDOW_SECONDS).floor }.uniq.length }
          minutes.call(positioned).fdiv(minutes.call(@records))
        end

        # One recording segment per timer stop, in document order. The closer
        # decides whether an unfinished run of fewer than two points is
        # dropped (every recording segment is) and whether elevation
        # placeholders are resolved (only a positioned segment needs them).
        def split_segments(records, marks: @stop_marks)
          marks = marks.sort
          segments = []
          current = []

          records.each do |point|
            while marks.first && marks.first <= point.time
              marks.shift
              yield(segments, current)
              current = []
            end
            current << point
          end
          yield(segments, current)
          segments
        end

        def close_segment(segments, points)
          resolved = Allure::Gpx::ElevationPlaceholders.resolve(points)
          segments << Allure::Gpx::Segment.new(points: resolved) if resolved.length >= 2
        end

        # A registered virtual platform draws its positions; the ergometer's
        # recorded lap distance is the real one (docs/dev/VIRTUAL-PLATFORMS.md).
        def calibrate_virtual_distance(segments)
          return segments unless Allure::Virtual::Platforms.for_file_id(@file_id)

          Allure::Virtual::DistanceCalibration.call(segments:, laps: @laps)
        end

        def activity_signals
          value = SportCatalog.alias_for(
            sport: Profile.sport(@session&.dig(:sport)),
            sub_sport: Profile.sub_sport(@session&.dig(:sub_sport))
          )
          return [] if value.nil?

          # Exactly one signal. Emitting sport and sub_sport separately would
          # resolve to two sports at equal confidence and trigger the
          # detector's ambiguity guard, falling back instead of detecting.
          [ Allure::Gpx::ActivitySignal.new(source: :fit_sport, value:) ]
        end

        def commute_hint
          SportCatalog.commute?(
            sport: Profile.sport(@session&.dig(:sport)),
            sub_sport: Profile.sub_sport(@session&.dig(:sub_sport))
          )
        end

        # Display value only. It reaches `ActivityDetector` at confidence 30,
        # below the automatic threshold, so an unnamed manufacturer never
        # changes a detected sport. A registered virtual platform is named from
        # its file_id fingerprint first: EXR writes no product name at all.
        # Most devices (every Garmin among them) write no product name either,
        # so the product code names the model before the manufacturer alone.
        def creator
          manufacturer = @file_id&.dig(:manufacturer)
          [
            Allure::Virtual::Platforms.creator_for(@file_id),
            @file_id&.dig(:product_name),
            Devices.product(manufacturer, @file_id&.dig(:product)),
            Devices.manufacturer(manufacturer),
            @device_info&.dig(:product_name),
            Devices.manufacturer(@device_info&.dig(:manufacturer))
          ].compact.first
        end

        def decode_time(value)
          return nil unless value.is_a?(Integer)
          return nil if value < MIN_UTC_TIMESTAMP

          Time.at(EPOCH_OFFSET + value).utc
        end

        def decode_coordinate(value, minimum, maximum, label)
          return nil unless value.is_a?(Integer)

          # The profile defines position_lat/position_long as sint32, but some
          # devices declare them uint32 and write two's-complement negative
          # semicircles. Reinterpreting the sign recovers the western and
          # southern hemispheres instead of turning -71.1 into 288.9.
          value -= 2**32 if value >= 2**31
          degrees = value * SEMICIRCLES_TO_DEGREES
          unless degrees.finite? && degrees >= minimum && degrees <= maximum
            raise Allure::Gpx::InvalidPointError, "#{label} out of range: #{degrees}"
          end

          degrees
        end

        def decode_altitude(fields)
          raw = fields[:enhanced_altitude] || fields[:altitude]
          return nil unless raw.is_a?(Numeric)

          value = (raw - ALTITUDE_RAW_OFFSET) / ALTITUDE_SCALE
          value.finite? ? value : nil
        end

        # Devices write 0 bpm for strap dropouts; 0 is never a valid
        # heart rate, while 0 cadence/power (coasting) stays valid.
        def positive_heart_rate(value)
          value if value.is_a?(Numeric) && value.positive?
        end
      end
      private_constant :Run
    end
  end
end
