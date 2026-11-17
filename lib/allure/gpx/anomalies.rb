# frozen_string_literal: true

module Allure
  module Gpx
    # Flags readings that look wrong in a recording: GPS positions, timestamps,
    # heart rate, elevation, power, and cadence. It only reports; no metric is
    # changed by a finding, except that the GPS positions `Outliers` already
    # rejected are reported here too, with their coordinates, so the owner can
    # see what the analysis left out.
    #
    # Pure and linear: local medians are computed only for the few intervals a
    # sliding mean already marks as candidates. Findings of one kind closer
    # than `MERGE_SECONDS` merge into one range carrying the worst value and a
    # count. Distances follow the workout-cumulative convention of
    # `TrackSeries`/`ChartSeries`, so the map and the chart place a finding
    # exactly where the stored points are.
    #
    # See PLAN_M1.md section 8.10 for the locked contract.
    class Anomalies
      KINDS = {
        "gps_rejected" => "gps",
        "gps_jump" => "gps",
        "speed_implausible" => "gps",
        "timestamp_skew" => "time",
        "recording_gap" => "time",
        "hr_missing" => "heart_rate",
        "hr_frozen" => "heart_rate",
        "hr_jump" => "heart_rate",
        "hr_out_of_range" => "heart_rate",
        "elevation_step" => "elevation",
        "elevation_mismatch" => "elevation",
        "power_spike" => "power",
        "cadence_spike" => "cadence"
      }.freeze

      # The fastest plausible speed over `SPEED_WINDOW_SECONDS` per sport, in
      # km/h. A sport absent from the table (skiing, sailing, paragliding,
      # virtual sports) is never checked against a ceiling.
      SPEED_CEILINGS_KM_H = {
        "walking" => 20.0, "hiking" => 20.0, "mountaineering" => 20.0, "snowshoes" => 20.0,
        "running" => 36.0, "trail" => 36.0,
        "tennis_outdoor" => 36.0, "padel_outdoor" => 36.0,
        "open_water_swimming" => 15.0, "swimrun" => 36.0,
        "rowing" => 30.0, "kayaking" => 30.0, "canoeing" => 30.0, "standup_paddleboarding" => 25.0,
        "inline_skating" => 70.0,
        "cycling" => 120.0, "cycling_road" => 120.0, "cycling_gravel" => 120.0, "cycling_electric" => 120.0,
        "cycling_trekking" => 120.0, "mountain_biking" => 120.0, "mountain_biking_electric" => 120.0,
        "halfbike" => 120.0
      }.freeze

      MAX_PER_KIND = 100
      MERGE_SECONDS = 10.0
      NEIGHBOURHOOD = 15
      CANDIDATE_RATIO = 1.5

      JUMP_MIN_KM_H = 15.0
      JUMP_RATIO = 3.0
      JUMP_MARGIN_KM_H = 15.0
      JUMP_MIN_METRES = 8.0

      SKEW_DURATION_RATIO = 1.5
      SKEW_FAST_RATIO = 1.5
      SKEW_MARGIN_KM_H = 10.0
      SKEW_TOLERANCE = 0.35
      SKEW_TOLERANCE_KM_H = 3.0
      DOUBLED_RATIO = 1.8
      DOUBLED_MAX_RATIO = 3.2
      DOUBLED_MULTIPLE_TOLERANCE = 0.2
      DOUBLED_NEIGHBOUR_TOLERANCE = 0.3

      SPEED_WINDOW_SECONDS = 10.0

      GAP_MIN_SECONDS = 10.0
      GAP_MEDIAN_FACTOR = 5.0
      GAP_TAIL_PERCENTILE = 0.95
      GAP_TAIL_FACTOR = 2.0
      GAP_MIN_METRES = 20.0

      HR_MIN_COVERAGE = 0.1
      HR_MISSING_SECONDS = 10.0
      HR_MISSING_SPACINGS = 8
      HR_FROZEN_SECONDS = 10.0
      HR_FROZEN_SAMPLES = 8
      HR_FROZEN_FOLLOWING_SECONDS = 5.0
      HR_JUMP_BPM = 25
      HR_JUMP_SECONDS = 3.0
      HR_SUSTAIN_SECONDS = 5.0
      HR_SUSTAIN_BPM = 10
      HR_RECOVERY_BPM = 10
      HR_RECOVERY_MAX_SECONDS = 120.0
      HR_SETTLE_SECONDS = 10.0
      HR_RANGE = (30..220)

      ELEVATION_STEP_METRES = 10.0
      ELEVATION_RATE_M_S = 5.0

      # A gap of this size between two passages of the same ground makes the
      # recorded ascent wrong; a small one is ordinary sensor behaviour. The
      # figure is only contested when it also reaches a tenth of the ascent,
      # so a mountain ride with a few tens of metres of drift stays usable.
      ASCENT_MISMATCH_METRES = 15.0
      ASCENT_MISMATCH_RATIO = 0.1

      POWER_CEILING_W = 2500
      POWER_SPIKE_FLOOR_W = 1000
      POWER_SPIKE_RATIO = 4.0
      CADENCE_CEILING = 250
      CADENCE_SPIKE_FLOOR = 150
      CADENCE_SPIKE_RATIO = 2.5

      # Impact (section 8.10): a finding is `major` when removing it changes a
      # displayed figure beyond the device's ordinary error, `minor` otherwise.
      IMPACT_SPEED_MARGIN_KM_H = 3.0
      IMPACT_SPEED_RATIO = 1.15
      IMPACT_DISTANCE_RATIO = 0.03
      IMPACT_HEART_RATE_BPM = 5
      DEVICE_SPEED_COVERAGE = 0.8
      CONTESTED_EFFORT_RATIO = 0.01
      SPEED_KINDS = %w[gps_rejected gps_jump speed_implausible timestamp_skew].freeze
      REPAIRED_KINDS = %w[gps_jump speed_implausible].freeze
      HEART_RATE_PEAK_KINDS = %w[hr_jump hr_out_of_range].freeze

      # The workout columns a record must not read while their figure is
      # contested: best pace is the maximum speed's inverse.
      CONTESTED_COLUMNS = {
        "max_speed" => %w[max_speed best_pace],
        "distance" => %w[distance],
        "ascent" => %w[ascent]
      }.freeze

      ImpactInterval = Data.define(:segment, :duration, :length, :repaired, :device_speed, :start_distance, :end_distance)
      ImpactRate = Data.define(:rate, :distance, :excluded)

      def self.speed_ceiling_for(slug) = SPEED_CEILINGS_KM_H[slug.to_s]

      def self.family_of(kind) = KINDS.fetch(kind.to_s)

      # The record columns a stored result contests.
      def self.contested_columns(data)
        impact = (data || {})["impact"] || {}
        impact.keys.flat_map { |key| CONTESTED_COLUMNS.fetch(key, []) }.uniq.sort
      end

      # A standard-distance effort is contested when the GPS distance the
      # anomalies added inside it reaches 1 % of its length: its time would be
      # a record the athlete never ran.
      def self.contested_effort?(data, start_distance:, end_distance:)
        return false if start_distance.nil? || end_distance.nil?

        length = end_distance.to_f - start_distance.to_f
        return false unless length.positive?

        excess = Array((data || {})["findings"]).sum do |finding|
          next 0.0 unless REPAIRED_KINDS.include?(finding["kind"])
          next 0.0 if finding["end_distance"].to_f < start_distance || finding["start_distance"].to_f > end_distance

          finding.dig("detail", "excess").to_f
        end
        excess >= CONTESTED_EFFORT_RATIO * length
      end

      # `segment_metrics` are the analyzer's `SegmentMetrics`, index-aligned
      # with `cleaned_segments`: their serialized points carry the distances.
      # `recorded_max_speed` is the workout's stored maximum (m/s), whatever
      # its source, so the impact compares what the owner reads.
      # `elevation_filter` is the workout's stored class: a terrain (`dem`)
      # profile is coherent with itself by construction, so the whole-workout
      # consistency check is skipped for it.
      def initialize(raw_segments:, cleaned_segments:, segment_metrics:, started_at:,
                     speed_ceiling_km_h: nil, stopped_speed_threshold_km_h: 0.0, records_elevation: true,
                     recorded_max_speed: nil, elevation_filter: nil)
        @raw_segments = raw_segments
        @cleaned_segments = cleaned_segments
        @segment_metrics = segment_metrics
        @started_at = started_at
        @speed_ceiling_km_h = speed_ceiling_km_h&.to_f
        @stopped_speed_threshold_km_h = stopped_speed_threshold_km_h.to_f
        @records_elevation = records_elevation
        @recorded_max_speed = recorded_max_speed&.to_f
        @elevation_filter = elevation_filter&.to_sym
      end

      # Returns `{ "findings" => [...], "counts" => { kind => total },
      # "impact" => { figure => ... } }`, or an empty hash for a clean
      # recording. Every finding carries its `tier`.
      def call
        findings = []
        scans = []
        offset = 0.0
        @cleaned_segments.each_with_index do |points, index|
          metrics = @segment_metrics[index]
          scan = SegmentScan.new(self, @raw_segments[index], points, metrics.points, offset, index)
          findings.concat(scan.call)
          scans << scan
          offset += metrics.distance.to_f
        end
        if checks_elevation_consistency?
          findings.concat(ElevationConsistency.findings(scans.flat_map(&:elevation_samples)))
        end
        assess(summarize(findings), scans)
      end

      attr_reader :started_at, :speed_ceiling_km_h, :stopped_speed_threshold_km_h, :records_elevation

      private

      # A terrain profile is coherent with itself; a positionless recording
      # and a sport that records no elevation have nothing to compare.
      def checks_elevation_consistency?
        @records_elevation && @elevation_filter != :dem
      end

      def assess(result, scans)
        findings = result.fetch("findings", [])
        intervals = scans.flat_map(&:impact_intervals)
        rates = scans.flat_map(&:impact_rates)
        findings.each { |finding| finding["tier"] = "minor" }
        record_excess(findings, intervals)

        impact = {
          "max_speed" => max_speed_impact(intervals, findings),
          "distance" => distance_impact(intervals, findings),
          "max_heart_rate" => heart_rate_impact(rates, findings),
          "ascent" => ascent_impact(findings)
        }.compact
        return result if impact.empty?

        { "findings" => findings, "counts" => result.fetch("counts", {}) }.merge("impact" => impact)
      end

      def record_excess(findings, intervals)
        findings.each do |finding|
          next unless REPAIRED_KINDS.include?(finding["kind"])

          excess = intervals.sum do |interval|
            inside = interval.start_distance >= finding["start_distance"] - 0.05 &&
                     interval.end_distance <= finding["end_distance"] + 0.05
            inside ? interval.length - interval.repaired : 0.0
          end
          finding["detail"]["excess"] = excess.round
        end
      end

      # The plausible maximum comes from the device's own (Doppler) speed when
      # the file carries it, otherwise from the track with the flagged
      # intervals brought back to their surroundings.
      def max_speed_impact(intervals, findings)
        recorded = @recorded_max_speed
        return nil unless recorded&.positive?

        timed = intervals.select { |interval| interval.duration.positive? }
        return nil if timed.empty?

        device = timed.count(&:device_speed) >= DEVICE_SPEED_COVERAGE * timed.length
        plausible, = if device
          window_maximum(intervals) { |interval| interval.device_speed.to_f * interval.duration }
        else
          window_maximum(intervals, &:repaired)
        end
        return nil unless plausible&.positive?
        return nil unless (recorded - plausible) * 3.6 >= IMPACT_SPEED_MARGIN_KM_H && recorded >= IMPACT_SPEED_RATIO * plausible

        _speed, first, last = window_maximum(intervals, &:length)
        start_distance = first ? intervals[first].start_distance : nil
        end_distance = last ? intervals[last].end_distance : nil
        mark_major(findings, SPEED_KINDS, start_distance, end_distance) if start_distance
        {
          "recorded" => recorded.round(2),
          "plausible" => plausible.round(2),
          "basis" => device ? "device" : "track",
          "start_distance" => start_distance&.round(1),
          "end_distance" => end_distance&.round(1)
        }.compact
      end

      # The fastest window of at least `SPEED_WINDOW_SECONDS` within one
      # recording segment, as `[speed, first index, last index]`.
      def window_maximum(intervals)
        best = nil
        left = 0
        distance = 0.0
        duration = 0.0
        intervals.each_with_index do |interval, right|
          if interval.segment != intervals[left].segment
            left = right
            distance = 0.0
            duration = 0.0
          end
          distance += yield(interval)
          duration += interval.duration
          while left < right && duration - intervals[left].duration >= SPEED_WINDOW_SECONDS
            distance -= yield(intervals[left])
            duration -= intervals[left].duration
            left += 1
          end
          next if duration < SPEED_WINDOW_SECONDS

          speed = distance / duration
          best = [ speed, left, right ] if best.nil? || speed > best.first
        end
        best || [ nil, nil, nil ]
      end

      def distance_impact(intervals, findings)
        recorded = @segment_metrics.sum { |metrics| metrics.distance.to_f }
        excess = intervals.sum { |interval| interval.length - interval.repaired }
        return nil unless recorded.positive? && excess >= IMPACT_DISTANCE_RATIO * recorded

        findings.each do |finding|
          finding["tier"] = "major" if REPAIRED_KINDS.include?(finding["kind"]) && finding["detail"]["excess"].to_i.positive?
        end
        { "recorded" => recorded.round, "plausible" => (recorded - excess).round }
      end

      # A gap between two passages of the same ground inflates the recorded
      # ascent; unlike the other figures there is no way to estimate the true
      # profile from the track itself, so the impact names the biggest gap
      # instead of a plausible value. It contests the ascent when that gap is
      # significant on its own and against the figure it spoils; the worst
      # gap is the one a stretch actually reaches, so a disagreement that
      # widens from 12 to 25 metres is read as 25.
      def ascent_impact(findings)
        mismatches = findings.select { |finding| finding["kind"] == "elevation_mismatch" }
        return nil if mismatches.empty?

        worst = mismatches.max_by { |finding| finding["detail"]["peak"].to_f }
        gap = worst["detail"]["peak"].to_f
        recorded = @segment_metrics.sum { |metrics| metrics.ascent.to_f }
        return nil unless gap >= ASCENT_MISMATCH_METRES && gap >= ASCENT_MISMATCH_RATIO * recorded

        mismatches.each do |finding|
          finding["tier"] = "major" if finding["detail"]["peak"].to_f >= ASCENT_MISMATCH_METRES
        end
        {
          "recorded" => recorded.round,
          "gap" => gap.round(1),
          "start_distance" => worst["start_distance"],
          "end_distance" => worst["end_distance"]
        }
      end

      # A peak inside an upward jump or out of range is not a reading.
      def heart_rate_impact(rates, findings)
        readings = rates.select(&:rate)
        return nil if readings.empty?

        peak = readings.max_by(&:rate)
        kept = readings.reject(&:excluded).map(&:rate).max
        return nil unless kept && peak.rate - kept >= IMPACT_HEART_RATE_BPM

        culprit = findings.find do |finding|
          HEART_RATE_PEAK_KINDS.include?(finding["kind"]) &&
            peak.distance.between?(finding["start_distance"] - 0.05, finding["end_distance"] + 0.05)
        end
        culprit&.store("tier", "major")
        {
          "recorded" => peak.rate,
          "plausible" => kept,
          "start_distance" => (culprit ? culprit["start_distance"] : peak.distance).round(1),
          "end_distance" => (culprit ? culprit["end_distance"] : peak.distance).round(1)
        }
      end

      def mark_major(findings, kinds, start_distance, end_distance)
        findings.each do |finding|
          next unless kinds.include?(finding["kind"])
          next if finding["end_distance"] < start_distance || finding["start_distance"] > end_distance

          finding["tier"] = "major"
        end
      end

      def summarize(findings)
        merged = findings.group_by { |finding| finding["kind"] }.flat_map { |kind, list| merge(kind, list) }
        return {} if merged.empty?

        counts = merged.group_by { |finding| finding["kind"] }.transform_values(&:length)
        kept = merged.group_by { |finding| finding["kind"] }.flat_map do |_kind, list|
          list.sort_by { |finding| finding["start_time"] }.first(MAX_PER_KIND)
        end
        {
          "findings" => kept.sort_by { |finding| [ finding["start_distance"], finding["start_time"] ] },
          "counts" => KINDS.keys.filter_map { |kind| [ kind, counts[kind] ] if counts[kind] }.to_h
        }
      end

      # The rejected positions keep their own coordinates, so they never merge.
      def merge(kind, list)
        sorted = list.sort_by { |finding| finding["start_time"] }
        return sorted if kind == "gps_rejected"

        sorted.each_with_object([]) do |finding, result|
          previous = result.last
          if previous && finding["start_time"] - previous["end_time"] <= MERGE_SECONDS
            worst = finding["detail"]["value"].to_f.abs > previous["detail"]["value"].to_f.abs ? finding : previous
            count = previous["detail"].fetch("count", 1) + finding["detail"].fetch("count", 1)
            previous["detail"] = worst["detail"].merge("count" => count)
            previous["detail"].delete("excess")
            previous["end_time"] = [ previous["end_time"], finding["end_time"] ].max
            previous["end_distance"] = [ previous["end_distance"], finding["end_distance"] ].max
          else
            result << finding
          end
        end
      end

      # One recording segment. Indexes are positions in the cleaned points,
      # which are index-aligned with the serialized points.
      class SegmentScan
        def initialize(owner, raw, points, serialized, offset, segment_index)
          @owner = owner
          @raw = raw
          @points = points
          @serialized = serialized
          @segment_index = segment_index
          @distances = serialized.map { |point| offset + point.fetch(PointSerializer::KEY_DISTANCE).to_f }
          @times = points.map { |point| (point.time - owner.started_at).to_f }
          build_intervals
          @findings = []
          @excluded_rates = Set.new
        end

        # Per-interval track lengths, the same with flagged movement brought
        # back to its surroundings, and the device's own speed: the inputs of
        # the impact assessment.
        def impact_intervals
          @durations.each_index.map do |index|
            ImpactInterval.new(
              segment: @segment_index, duration: @durations[index], length: @lengths[index],
              repaired: @repaired[index], device_speed: @points[index + 1].speed,
              start_distance: @distances[index], end_distance: @distances[index + 1]
            )
          end
        end

        def impact_rates
          @points.each_with_index.map do |point, index|
            rate = point.heart_rate if point.heart_rate.is_a?(Numeric) && point.heart_rate.positive?
            ImpactRate.new(rate:, distance: @distances[index], excluded: @excluded_rates.include?(index))
          end
        end

        # The canonical elevation and the workout-cumulative position of every
        # point carrying both, for the whole-workout consistency check: the
        # serialized elevation is the profile the ascent was measured from.
        def elevation_samples
          @points.each_index.filter_map do |index|
            elevation = @serialized[index][PointSerializer::KEY_ELEVATION]
            point = @points[index]
            next if elevation.nil? || !point.positioned?

            ElevationConsistency::Sample.new(
              distance: @distances[index],
              time: @times[index],
              elevation: elevation.to_f,
              latitude: point.latitude,
              longitude: point.longitude,
              segment: @segment_index
            )
          end
        end

        def call
          return [] if @points.length < 2

          # A positionless segment has no positions to judge: the GPS family
          # (rejected fixes, jumps, skew, implausible speed) never runs, and
          # the time, heart-rate, power and cadence families do
          # (docs/dev/NO-GPS.md). Nothing is marked major, because no derived
          # figure depends on a coordinate here.
          if positioned?
            rejected_positions
            speed_patterns
            implausible_speed
          end
          recording_gaps
          heart_rate
          elevation_steps if @owner.records_elevation
          spikes(:power, "power_spike", ceiling: POWER_CEILING_W, floor: POWER_SPIKE_FLOOR_W, ratio: POWER_SPIKE_RATIO)
          spikes(:cadence, "cadence_spike", ceiling: CADENCE_CEILING, floor: CADENCE_SPIKE_FLOOR, ratio: CADENCE_SPIKE_RATIO)
          @findings
        end

        private

        def positioned? = @points.first&.positioned? || false

        def build_intervals
          @durations = []
          @lengths = []
          @speeds = []
          @points.each_cons(2) do |previous_point, point|
            duration = [ point.time - previous_point.time, 0.0 ].max.to_f
            length = if positioned?
              Geo.horizontal_distance(previous_point.latitude, previous_point.longitude, point.latitude, point.longitude)
            else
              0.0
            end
            @durations << duration
            @lengths << length
            @speeds << (duration.positive? && positioned? ? length / duration * 3.6 : nil)
          end
          @repaired = @lengths.dup
          build_speed_sums
        end

        # Prefix sums over the interval speeds give an O(1) neighbourhood mean,
        # the cheap pre-filter in front of the exact local median.
        def build_speed_sums
          @speed_sum = [ 0.0 ]
          @speed_count = [ 0 ]
          @speeds.each do |speed|
            @speed_sum << @speed_sum.last + (speed || 0.0)
            @speed_count << @speed_count.last + (speed ? 1 : 0)
          end
        end

        def neighbourhood_mean(index)
          low = [ index - NEIGHBOURHOOD, 0 ].max
          high = [ index + NEIGHBOURHOOD, @speeds.length - 1 ].min
          sum = @speed_sum[high + 1] - @speed_sum[low] - (@speeds[index] || 0.0)
          count = @speed_count[high + 1] - @speed_count[low] - (@speeds[index] ? 1 : 0)
          count.positive? ? sum / count : nil
        end

        def neighbourhood_median(index, exclude: [ index ])
          low = [ index - NEIGHBOURHOOD, 0 ].max
          high = [ index + NEIGHBOURHOOD, @speeds.length - 1 ].min
          values = (low..high).filter_map { |position| @speeds[position] unless exclude.include?(position) }
          median(values)
        end

        # `coordinates` are the rejected positions themselves; `path` joins them
        # to their surviving neighbours, the way the map draws them.
        def add(kind, first, last, detail, coordinates: nil, path: nil)
          finding = {
            "kind" => kind,
            "start_distance" => @distances[first].round(1),
            "end_distance" => @distances[last].round(1),
            "start_time" => @times[first].round,
            "end_time" => @times[last].round,
            "detail" => detail
          }
          finding["coordinates"] = coordinates if coordinates
          finding["path"] = path if path
          @findings << finding
        end

        # Raw points absent from the cleaned stream. `Outliers` returns the
        # very same objects, so identity tells kept from rejected even when two
        # samples are equal values.
        def rejected_positions
          cursor = 0
          runs = []
          @raw.each do |point|
            if cursor < @points.length && point.equal?(@points[cursor])
              cursor += 1
            elsif runs.last && runs.last[:position] == cursor
              runs.last[:points] << point
            else
              runs << { position: cursor, points: [ point ] }
            end
          end

          runs.each do |run|
            before = run[:position] - 1
            after = run[:position]
            first = before.negative? ? 0 : before
            last = after >= @points.length ? @points.length - 1 : after
            anchors_before = before.negative? ? [] : [ coordinate(@points[before]) ]
            anchors_after = after >= @points.length ? [] : [ coordinate(@points[after]) ]
            rejected = run[:points].map { |point| coordinate(point) }
            add("gps_rejected", first, last, { "value" => rejected.length, "count" => rejected.length },
                coordinates: rejected, path: anchors_before + rejected + anchors_after)
          end
        end

        def coordinate(point) = [ point.longitude.round(6), point.latitude.round(6) ]

        # Timestamp skews first, so an interval explained by a shifted or
        # missing sample is never also reported as a GPS jump.
        def speed_patterns
          explained = Set.new
          @speeds.each_index do |index|
            next if explained.include?(index)

            if (pair = skewed_pair(index))
              explained << index << index + 1
              add("timestamp_skew", index, index + 2, pair)
            elsif (doubled = doubled_interval(index))
              explained << index
              add("timestamp_skew", index, index + 1, doubled)
            end
          end

          @speeds.each_index do |index|
            next if explained.include?(index)

            jump = gps_jump(index)
            next unless jump

            @repaired[index] = [ @lengths[index], jump.delete(:surrounding) / 3.6 * @durations[index] ].min
            add("gps_jump", index, index + 1, jump)
          end
        end

        # One sample stamped a second early or late: a too-fast interval next
        # to a too-slow one of a different duration, whose combined speed is
        # the surrounding speed.
        def skewed_pair(index)
          following = index + 1
          return nil if following >= @speeds.length

          first, second = @speeds[index], @speeds[following]
          return nil unless first && second

          short, long = [ @durations[index], @durations[following] ].minmax
          return nil unless long >= SKEW_DURATION_RATIO * short

          pair = (@lengths[index] + @lengths[following]) / (@durations[index] + @durations[following]) * 3.6
          fast, slow = [ first, second ].max, [ first, second ].min
          return nil unless fast >= SKEW_FAST_RATIO * pair && fast - pair >= SKEW_MARGIN_KM_H
          return nil unless slow <= pair / SKEW_FAST_RATIO

          surrounding = neighbourhood_median(index, exclude: [ index, following ])
          return nil unless surrounding && (pair - surrounding).abs <= SKEW_TOLERANCE * surrounding + SKEW_TOLERANCE_KM_H

          { "value" => fast.round(1), "speed" => fast.round(1), "corrected" => pair.round(1) }
        end

        # A missing sample: one short interval covering a whole multiple of
        # the surrounding step, between two ordinary ones.
        def doubled_interval(index)
          speed = @speeds[index]
          return nil unless speed && speed >= SKEW_MARGIN_KM_H && @durations[index] <= 2.0
          return nil unless (mean = neighbourhood_mean(index)) && speed >= CANDIDATE_RATIO * mean

          surrounding = neighbourhood_median(index)
          return nil unless surrounding&.positive?

          ratio = speed / surrounding
          return nil unless ratio >= DOUBLED_RATIO && ratio <= DOUBLED_MAX_RATIO && speed - surrounding >= SKEW_MARGIN_KM_H
          return nil unless (ratio - ratio.round).abs <= DOUBLED_MULTIPLE_TOLERANCE
          return nil unless ordinary_neighbours?(index, surrounding)

          { "value" => speed.round(1), "speed" => speed.round(1), "corrected" => surrounding.round(1) }
        end

        def ordinary_neighbours?(index, surrounding)
          [ index - 1, index + 1 ].all? do |position|
            neighbour = position.between?(0, @speeds.length - 1) ? @speeds[position] : surrounding
            neighbour && (neighbour - surrounding).abs <= DOUBLED_NEIGHBOUR_TOLERANCE * surrounding
          end
        end

        def gps_jump(index)
          speed = @speeds[index]
          return nil unless speed && speed > JUMP_MIN_KM_H && @lengths[index] >= JUMP_MIN_METRES
          return nil unless (mean = neighbourhood_mean(index)) && speed >= CANDIDATE_RATIO * mean

          surrounding = neighbourhood_median(index)
          return nil unless surrounding
          return nil unless speed >= JUMP_RATIO * surrounding && speed - surrounding >= JUMP_MARGIN_KM_H

          { "value" => speed.round(1), "speed" => speed.round(1), "metres" => @lengths[index].round,
            surrounding: surrounding }
        end

        # Sliding windows of at least `SPEED_WINDOW_SECONDS` faster than the
        # sport could ever go; overlapping windows merge downstream.
        def implausible_speed
          ceiling = @owner.speed_ceiling_km_h
          return unless ceiling

          left = 0
          distance = 0.0
          duration = 0.0
          flagged = Set.new
          @durations.each_index do |right|
            distance += @lengths[right]
            duration += @durations[right]
            while left < right && duration - @durations[left] >= SPEED_WINDOW_SECONDS
              distance -= @lengths[left]
              duration -= @durations[left]
              left += 1
            end
            next if duration < SPEED_WINDOW_SECONDS

            speed = distance / duration * 3.6
            next unless speed > ceiling

            (left..right).each { |index| flagged << index }
            add("speed_implausible", left, right + 1, { "value" => speed.round(1), "speed" => speed.round(1), "ceiling" => ceiling.round })
          end
          repair_implausible(flagged, ceiling)
        end

        # Brought back to the surrounding speed outside the flagged stretch,
        # never above the sport's ceiling.
        def repair_implausible(flagged, ceiling)
          flagged.each do |index|
            surrounding = neighbourhood_median(index, exclude: flagged) || ceiling
            cap = [ surrounding, ceiling ].min / 3.6 * @durations[index]
            @repaired[index] = [ @repaired[index], cap ].min
          end
        end

        # Samples missing while the athlete kept moving; a real stop covers
        # almost no ground and is a pause, not a gap.
        def recording_gaps
          positive = @durations.select(&:positive?)
          return if positive.empty?

          # Smart recording writes on its own irregular rhythm: the threshold
          # follows the file's usual spacing as well as its long tail.
          sorted = positive.sort
          tail = sorted[((sorted.length - 1) * GAP_TAIL_PERCENTILE).floor]
          threshold = [ GAP_MIN_SECONDS, GAP_MEDIAN_FACTOR * median(positive), GAP_TAIL_FACTOR * tail ].max
          moving = [ @owner.stopped_speed_threshold_km_h, 1.0 ].max
          @durations.each_index do |index|
            duration = @durations[index]
            next unless duration >= threshold && @lengths[index] >= GAP_MIN_METRES
            next unless @lengths[index] / duration * 3.6 > moving

            add("recording_gap", index, index + 1,
                { "value" => duration.round, "seconds" => duration.round, "metres" => @lengths[index].round })
          end
        end

        def heart_rate
          rates = @points.map { |point| point.heart_rate if point.heart_rate.is_a?(Numeric) && point.heart_rate.positive? }
          return if rates.count(&:itself) < HR_MIN_COVERAGE * rates.length

          absorbed = frozen_heart_rate(rates)
          missing_heart_rate(rates, absorbed)
          heart_rate_jumps(rates)
          heart_rate_out_of_range(rates)
        end

        # [first, last] index runs where the block holds.
        def runs(values)
          result = []
          values.each_with_index do |value, index|
            next unless yield(value, index)

            if result.last && result.last[1] == index - 1
              result.last[1] = index
            else
              result << [ index, index ]
            end
          end
          result
        end

        # The run's duration up to the next sample, or to its own last one at
        # the end of the recording.
        def run_seconds(first, last)
          stop = last + 1 < @times.length ? last + 1 : last
          @times[stop] - @times[first]
        end

        def run_end(last) = last + 1 < @times.length ? last + 1 : last

        # A sensor that loses its signal often repeats its last value for a
        # while before the device stops recording it: the held value is not a
        # reading.
        def frozen_heart_rate(rates)
          missing = runs(rates) { |rate| rate.nil? }.to_h { |first, last| [ first, last ] }
          absorbed = Set.new
          index = 0
          while index < rates.length
            rate = rates[index]
            last = index
            last += 1 while rate && last + 1 < rates.length && rates[last + 1] == rate
            following = missing[last + 1]
            if rate && following && last - index + 1 >= HR_FROZEN_SAMPLES &&
               @times[last] - @times[index] >= HR_FROZEN_SECONDS &&
               run_seconds(last + 1, following) >= HR_FROZEN_FOLLOWING_SECONDS
              absorbed << last + 1
              frozen = (@times[last + 1] - @times[index]).round
              add("hr_frozen", index, run_end(following),
                  { "value" => rate, "bpm" => rate, "frozen" => frozen, "missing" => run_seconds(last + 1, following).round })
            end
            index = last + 1
          end
          absorbed
        end

        # A sensor that writes every few seconds leaves short holes by design;
        # a hole counts only beyond several of its own usual spacings.
        def missing_heart_rate(rates, absorbed)
          threshold = [ HR_MISSING_SECONDS, HR_MISSING_SPACINGS * heart_rate_spacing(rates) ].max
          runs(rates) { |rate| rate.nil? }.each do |first, last|
            next if absorbed.include?(first)

            seconds = run_seconds(first, last)
            next if seconds < threshold

            position = if first.zero? then "start" elsif last == rates.length - 1 then "end" else "middle" end
            add("hr_missing", first, run_end(last), { "value" => seconds.round, "seconds" => seconds.round, "position" => position })
          end
        end

        def heart_rate_spacing(rates)
          sampled = rates.each_index.select { |index| rates[index] }
          spacings = sampled.each_cons(2).map { |first, second| @times[second] - @times[first] }
          median(spacings) || 0.0
        end

        # A sudden drop or rise that holds: the strap lost contact or locked
        # onto the cadence. The range runs until the reading comes back.
        def heart_rate_jumps(rates)
          index = 0
          while index < rates.length - 1
            before, after = rates[index], rates[index + 1]
            seconds = @times[index + 1] - @times[index]
            unless before && after && seconds <= HR_JUMP_SECONDS && (after - before).abs >= HR_JUMP_BPM &&
                   sustained?(rates, index + 1)
              index += 1
              next
            end

            last = recovery_index(rates, index + 1, before)
            (index + 1..last).each { |position| @excluded_rates << position } if after > before
            add("hr_jump", index, last,
                { "value" => (after - before).abs, "from" => before, "to" => after, "seconds" => seconds.round })
            index = [ last, index + 1 ].max
          end
        end

        def sustained?(rates, start)
          following = []
          position = start + 1
          while position < rates.length && @times[position] - @times[start] <= HR_SUSTAIN_SECONDS
            following << rates[position] if rates[position]
            position += 1
          end
          following.length >= 2 && (median(following) - rates[start]).abs <= HR_SUSTAIN_BPM
        end

        def recovery_index(rates, start, level)
          position = start
          settle = nil
          while position < rates.length && @times[position] - @times[start] <= HR_RECOVERY_MAX_SECONDS
            return position if rates[position] && (rates[position] - level).abs <= HR_RECOVERY_BPM

            settle ||= position if @times[position] - @times[start] >= HR_SETTLE_SECONDS
            position += 1
          end
          settle || [ position, rates.length - 1 ].min
        end

        def heart_rate_out_of_range(rates)
          runs(rates) { |rate| rate && !HR_RANGE.cover?(rate) }.each do |first, last|
            extreme = rates[first..last].max_by { |rate| (rate - 120).abs }
            (first..last).each { |position| @excluded_rates << position }
            add("hr_out_of_range", first, run_end(last), { "value" => extreme, "bpm" => extreme })
          end
        end

        def elevation_steps
          @points.each_cons(2).with_index do |(previous_point, point), index|
            next unless Elevation.valid?(previous_point.elevation) && Elevation.valid?(point.elevation)

            seconds = @durations[index]
            next unless seconds.positive?

            delta = point.elevation - previous_point.elevation
            next unless delta.abs >= ELEVATION_STEP_METRES && delta.abs / seconds >= ELEVATION_RATE_M_S

            add("elevation_step", index, index + 1, { "value" => delta.round(1), "metres" => delta.round(1), "seconds" => seconds.round })
          end
        end

        def spikes(attribute, kind, ceiling:, floor:, ratio:)
          values = @points.map { |point| point.public_send(attribute) if point.public_send(attribute).is_a?(Numeric) }
          return if values.none?

          values.each_with_index do |value, index|
            next unless value && value >= floor

            unless value >= ceiling
              low = [ index - NEIGHBOURHOOD, 0 ].max
              high = [ index + NEIGHBOURHOOD, values.length - 1 ].min
              surrounding = median((low..high).filter_map { |position| values[position] unless position == index })
              next unless surrounding && value >= ratio * surrounding
            end

            add(kind, index, [ index + 1, values.length - 1 ].min, { "value" => value, "reading" => value })
          end
        end

        def median(values)
          return nil if values.empty?

          sorted = values.sort
          middle = sorted.length / 2
          sorted.length.odd? ? sorted[middle].to_f : (sorted[middle - 1] + sorted[middle]) / 2.0
        end
      end
    end
  end
end
