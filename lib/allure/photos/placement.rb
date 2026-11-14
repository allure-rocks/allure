# frozen_string_literal: true

module Allure
  module Photos
    # Places a photo along a recording (PLAN_PHOTOS.md §4), pure and offline.
    #
    # `segments` are the recording segments in order, each `{ started_at:,
    # points: }` with the stored point hashes (`t` seconds from the segment
    # start, `d` cumulative metres, `lon`/`lat`). Coordinates are [longitude,
    # latitude] throughout.
    class Placement
      Result = Data.define(:longitude, :latitude, :source, :distance, :elapsed)
      Sample = Data.define(:time, :distance, :longitude, :latitude, :segment)
      # Why an automatic placement found nothing (PLAN_PHOTOS.md §4): the EXIF
      # position is further from the route than a photo can mean, and/or the
      # capture time falls outside the recording's window. Nil when neither
      # applies, or when there is no clue at all.
      Diagnosis = Data.define(:exif_metres, :before_start, :after_finish)

      EXIF_MAX_METRES = 200.0
      SNAP_MAX_METRES = 2_000.0
      TIME_WINDOW = 300
      EARTH_RADIUS = 6_371_008.8

      def initialize(segments:, started_at:)
        @started_at = started_at
        @samples = segments.each_with_index.flat_map do |segment, index|
          start = segment.fetch(:started_at)
          Array(segment.fetch(:points)).filter_map do |point|
            longitude = point["lon"]
            latitude = point["lat"]
            next unless longitude.is_a?(Numeric) && latitude.is_a?(Numeric)

            Sample.new(time: start + point["t"].to_f, distance: point["d"].to_f,
                       longitude: longitude.to_f, latitude: latitude.to_f, segment: index)
          end
        end
      end

      def positioned? = @samples.any?

      # EXIF position when it lies near the track, otherwise the capture time.
      def automatic(exif_longitude: nil, exif_latitude: nil, taken_at: nil)
        return unless positioned?

        if !exif_longitude.nil? && !exif_latitude.nil?
          nearest = nearest(exif_longitude, exif_latitude)
          if nearest && nearest[:metres] <= EXIF_MAX_METRES
            return Result.new(longitude: exif_longitude, latitude: exif_latitude, source: "exif",
                              distance: nearest[:distance], elapsed: nearest[:time] - @started_at)
          end
        end
        at_time(taken_at) if taken_at
      end

      # Why `automatic` answered nothing, in the owner's terms (PLAN_PHOTOS.md
      # §4): a GPS position beyond the 200 m threshold, and/or a capture time
      # beyond the five-minute window at either end. Nil when no clue explains
      # it, so the page can say the photo has neither.
      def diagnose(exif_longitude: nil, exif_latitude: nil, taken_at: nil)
        return unless positioned?

        exif_metres = nil
        if !exif_longitude.nil? && !exif_latitude.nil?
          nearest = nearest(exif_longitude, exif_latitude)
          exif_metres = nearest[:metres] if nearest && nearest[:metres] > EXIF_MAX_METRES
        end

        before_start = nil
        after_finish = nil
        if taken_at
          first = @samples.first.time
          last = @samples.last.time
          before_start = first - taken_at if taken_at < first - TIME_WINDOW
          after_finish = taken_at - last if taken_at > last + TIME_WINDOW
        end
        return if exif_metres.nil? && before_start.nil? && after_finish.nil?

        Diagnosis.new(exif_metres:, before_start:, after_finish:)
      end

      # The point of the track the owner pointed at, snapped onto the line.
      def snap(longitude, latitude)
        nearest = nearest(longitude, latitude)
        return unless nearest && nearest[:metres] <= SNAP_MAX_METRES

        Result.new(longitude: nearest[:longitude], latitude: nearest[:latitude], source: "manual",
                   distance: nearest[:distance], elapsed: nearest[:time] - @started_at)
      end

      def at_time(time)
        return if @samples.empty?

        first = @samples.first
        last = @samples.last
        return if time < first.time - TIME_WINDOW || time > last.time + TIME_WINDOW
        return result_at(first, time) if time <= first.time
        return result_at(last, time) if time >= last.time

        index = @samples.bsearch_index { it.time > time }
        after = @samples[index]
        before = @samples[index - 1]
        # Inside a pause between recording segments the athlete stood where
        # the previous segment ended.
        return result_at(before, time) if before.segment != after.segment || after.time <= before.time

        ratio = (time - before.time) / (after.time - before.time)
        Result.new(
          longitude: lerp(before.longitude, after.longitude, ratio),
          latitude: lerp(before.latitude, after.latitude, ratio),
          source: "time",
          distance: lerp(before.distance, after.distance, ratio),
          elapsed: time - @started_at
        )
      end

      private

      # The photo's own instant, at the nearest recorded spot.
      def result_at(sample, time)
        Result.new(longitude: sample.longitude, latitude: sample.latitude, source: "time",
                   distance: sample.distance, elapsed: time - @started_at)
      end

      # Nearest point on any recorded stretch, projected in a local plane
      # around the target: exact enough at the hundreds of metres that matter.
      def nearest(longitude, latitude)
        scale = Math.cos(latitude * Math::PI / 180)
        to_xy = ->(lon, lat) { [ (lon - longitude) * scale, lat - latitude ] }
        best = nil

        @samples.each_with_index do |sample, index|
          following = @samples[index + 1]
          candidate = if following && following.segment == sample.segment
            project(sample, following, to_xy)
          else
            { ratio: 0.0, squared: to_xy.call(sample.longitude, sample.latitude).sum { it * it } }
          end
          next if best && candidate[:squared] >= best[:squared]

          best = candidate.merge(from: sample, to: following && following.segment == sample.segment ? following : sample)
        end
        return unless best

        ratio = best[:ratio]
        from = best[:from]
        to = best[:to]
        {
          metres: Math.sqrt(best[:squared]) * Math::PI / 180 * EARTH_RADIUS,
          longitude: lerp(from.longitude, to.longitude, ratio),
          latitude: lerp(from.latitude, to.latitude, ratio),
          distance: lerp(from.distance, to.distance, ratio),
          time: lerp(from.time, to.time, ratio)
        }
      end

      def project(from, to, to_xy)
        ax, ay = to_xy.call(from.longitude, from.latitude)
        bx, by = to_xy.call(to.longitude, to.latitude)
        dx = bx - ax
        dy = by - ay
        length = (dx * dx) + (dy * dy)
        ratio = length.zero? ? 0.0 : (-((ax * dx) + (ay * dy)) / length).clamp(0.0, 1.0)
        px = ax + (ratio * dx)
        py = ay + (ratio * dy)
        { ratio:, squared: (px * px) + (py * py) }
      end

      def lerp(from, to, ratio) = from + ((to - from) * ratio)
    end
  end
end
