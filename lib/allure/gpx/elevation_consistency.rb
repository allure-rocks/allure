# frozen_string_literal: true

module Allure
  module Gpx
    # Flags a recording whose elevation contradicts itself: where the route
    # comes back to the same ground at least five minutes and three hundred
    # metres later, both passages should read the same altitude. A systematic
    # gap between them — a barometer that re-zeroed after a pause, a profile
    # that never referenced sea level, a sensor drifting over the outing —
    # inflates ascent and descent without showing anywhere else, and no
    # single-segment check can see it (docs/dev/WORKOUT.md).
    #
    # Pure and framework-independent, and it works on the whole workout
    # because the gap commonly appears at a resume, between two recording
    # segments. It samples the canonical (already filtered) profile so jitter
    # and stops cost nothing, pairs two passages by position on a grid, their
    # travel directions, and their distance and time apart, and only reports a
    # stretch of `STRETCH_METRES` or more whose gap holds `MISMATCH_METRES`.
    module ElevationConsistency
      SAMPLE_METRES = 20.0
      CELL_METRES = 20.0
      MATCH_METRES = 20.0
      MIN_GAP_METRES = 300.0
      MIN_GAP_SECONDS = 300.0
      # The absolute cosine of the angle between the two passages'
      # directions: only the same or the opposite way counts. A crossing
      # road, a bridge overhead, and a roundabout are not the same ground.
      DIRECTION_COS = 0.5
      # Two pairs belong to one stretch when both passages advance by at most
      # this many samples, in either direction: an out-and-back crosses its
      # own path the other way round.
      CHAIN_SAMPLES = 2
      STRETCH_METRES = 200.0
      MISMATCH_METRES = 10.0
      # The gaps of one stretch must hold together: two different paths a few
      # metres apart — a switchback, a cliff-side trail — read the terrain
      # itself and disagree by a value that moves with the position.
      SPREAD_METRES = 15.0
      # Each grid cell offers a sample at most its most recent eligible
      # passages, so a recording that keeps returning to the same ground (a
      # velodrome, a tight loop) stays linear instead of comparing every
      # sample with every earlier one.
      CELL_CANDIDATES = 16

      # One recorded sample: workout-cumulative distance, time from the
      # workout start, the canonical elevation, the position, and the
      # recording segment it belongs to.
      Sample = Data.define(:distance, :time, :elevation, :latitude, :longitude, :segment)

      module_function

      # `samples` are the workout's points in workout order. Returns finding
      # hashes in the shape `Anomalies` stores (`elevation_mismatch` kind).
      def findings(samples)
        points = resample(samples)
        return [] if points.length < 4

        directions = headings(points)
        chains(pairs(points, directions)).flat_map { |chain| mismatches(chain) }
      end

      # One point per `SAMPLE_METRES` along the workout, plus the first point
      # of every recording segment so a short one is never skipped whole.
      def resample(samples)
        points = []
        samples.each do |sample|
          next if points.any? && sample.segment == points.last.segment &&
                  sample.distance - points.last.distance < SAMPLE_METRES

          points << sample
        end
        points
      end

      # The unit travel direction of every sample, from its neighbours within
      # the same recording segment; nil when it cannot be told.
      def headings(points)
        points.each_index.map do |index|
          sample = points[index]
          previous = index.positive? && points[index - 1].segment == sample.segment ? points[index - 1] : nil
          following = points[index + 1]&.segment == sample.segment ? points[index + 1] : nil
          from = previous || sample
          to = following || sample
          north = (to.latitude - from.latitude) * 111_320.0
          east = (to.longitude - from.longitude) * 111_320.0 * Math.cos(sample.latitude * Math::PI / 180.0)
          length = Math.hypot(north, east)
          length.positive? ? [ north / length, east / length ] : nil
        end
      end

      # For every sample, the nearest earlier sample that stands on the same
      # ground: within `MATCH_METRES` on a grid, `MIN_GAP_METRES` and
      # `MIN_GAP_SECONDS` behind, and heading the same or the opposite way.
      # A cell lists its samples in workout order and both gaps only grow
      # along it, so the eligible ones are a prefix, of which only the last
      # `CELL_CANDIDATES` are compared, newest first: an exact tie goes to
      # the most recent passage, which every cell agrees on, so a stretch
      # ridden lap after lap keeps comparing with one lap.
      def pairs(points, directions)
        grid = Hash.new { |hash, key| hash[key] = [] }
        points.each_index.filter_map do |b_index|
          b = points[b_index]
          cell = cell(b)
          best = nil
          (-1..1).each do |row|
            (-1..1).each do |column|
              recent_eligible(grid.fetch([ cell[0] + row, cell[1] + column ], nil), points, b).reverse_each do |a_index|
                candidate = pair(points, directions, a_index, b_index)
                next unless candidate
                next if best && best[:distance] <= candidate[:distance]

                best = candidate
              end
            end
          end
          grid[cell] << b_index
          best
        end
      end

      def recent_eligible(indices, points, b)
        return [] if indices.nil?

        cut = indices.bsearch_index { |a_index| !far_enough?(points[a_index], b) } || indices.length
        indices[[ cut - CELL_CANDIDATES, 0 ].max...cut]
      end

      def far_enough?(a, b)
        b.time - a.time >= MIN_GAP_SECONDS && b.distance - a.distance >= MIN_GAP_METRES
      end

      def pair(points, directions, a_index, b_index)
        a = points[a_index]
        b = points[b_index]
        return nil unless far_enough?(a, b)

        direction_a = directions[a_index]
        direction_b = directions[b_index]
        return nil unless direction_a && direction_b

        dot = (direction_a[0] * direction_b[0]) + (direction_a[1] * direction_b[1])
        return nil if dot.abs < DIRECTION_COS

        apart = Geo.horizontal_distance(a.latitude, a.longitude, b.latitude, b.longitude)
        return nil if apart > MATCH_METRES

        { a_index:, b_index:, a:, b:, distance: apart, gap: b.elevation - a.elevation }
      end

      # Consecutive pairs whose two passages both keep advancing belong to one
      # stretch of shared ground.
      def chains(pairs)
        pairs.each_with_object([]) do |pair, chains|
          chain = chains.last
          last = chain&.last
          if last && (pair[:b_index] - last[:b_index]).abs <= CHAIN_SAMPLES &&
             (pair[:a_index] - last[:a_index]).abs <= CHAIN_SAMPLES
            chain << pair
          else
            chains << [ pair ]
          end
        end
      end

      # A maximal run of one chain whose gap holds the threshold with one
      # sign. The sign flipping means the two passages of that ground agree
      # again, so a flip ends the run like a value below the threshold does.
      def mismatches(chain)
        runs = []
        current = nil
        chain.each do |pair|
          consistent = pair[:gap].abs >= MISMATCH_METRES &&
                       (current.nil? || pair[:gap].positive? == current.first[:gap].positive?)
          if consistent
            current ? current << pair : current = [ pair ]
          elsif current
            runs << current
            current = nil
          end
        end
        runs << current if current
        runs.filter_map { |run| finding(run) }
      end

      def finding(run)
        first = run.first
        last = run.last
        return nil if last[:b].distance - first[:b].distance < STRETCH_METRES

        gaps = run.map { |pair| pair[:gap] }
        spread = spread(gaps)
        return nil if spread > SPREAD_METRES

        median_gap = median(gaps).round(1)
        {
          "kind" => "elevation_mismatch",
          "start_distance" => first[:b].distance.round(1),
          "end_distance" => last[:b].distance.round(1),
          "start_time" => first[:b].time.round,
          "end_time" => last[:b].time.round,
          "detail" => {
            "value" => median_gap,
            "metres" => median_gap.abs.round(1),
            "peak" => gaps.map(&:abs).max.round(1),
            "spread" => spread.round(1),
            "first_distance" => first[:a].distance.round(1),
            "first_time" => first[:a].time.round,
            "count" => run.length
          }
        }
      end

      # The interquartile range of a stretch's gaps: a systematic offset holds
      # one value, while two different paths (a switchback, a cliff-side
      # trail) read the terrain itself.
      def spread(gaps)
        sorted = gaps.sort
        upper = sorted[((sorted.length - 1) * 0.75).round]
        lower = sorted[((sorted.length - 1) * 0.25).round]
        upper - lower
      end

      def cell(sample)
        [
          (sample.latitude * 111_320.0 / CELL_METRES).floor,
          (sample.longitude * 111_320.0 * Math.cos(sample.latitude * Math::PI / 180.0) / CELL_METRES).floor
        ]
      end

      def median(values)
        sorted = values.sort
        middle = sorted.length / 2
        sorted.length.odd? ? sorted[middle].to_f : (sorted[middle - 1] + sorted[middle]) / 2.0
      end
    end
  end
end
