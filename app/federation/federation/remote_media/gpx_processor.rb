# frozen_string_literal: true

require "digest"
require "stringio"

module Federation
  module RemoteMedia
    # Turns a verified remote GPX into the immutable remote representation:
    # the cached blob, the sanitized track (segment_index only, like a local
    # publication), the bounded elevation chart, and route metadata. It never
    # creates a Workout, TrackSegment, or owner attachment.
    class GpxProcessor
      EPOCH = Time.utc(1970, 1, 1)
      SegmentAdapter = Data.define(:started_at, :points, :distance)

      # A minimal value satisfying SanitizedTrackSerializer's duck type.
      class FilteredValue
        attr_reader :segments

        def initialize(segments)
          @segments = segments
        end

        def usable? = segments.any?
      end

      def initialize(attachment:, body:, verified:, now: Time.current)
        @attachment = attachment
        @body = body
        @verified = verified
        @now = now
      end

      def call
        derived = derive
        blob = nil
        begin
          blob = ActiveStorage::Blob.create_and_upload!(
            io: StringIO.new(@body),
            filename: "#{@attachment.filename_stem}.gpx",
            content_type: @verified.content_type,
            identify: false
          )
          @attachment.update!(
            status: "cached",
            blob_id: blob.id,
            content_digest: Digest::SHA256.hexdigest(@body),
            byte_size: @verified.byte_size,
            fetched_at: @now,
            last_error: nil
          )
          @attachment.owner.attach_remote_media!(
            track: derived.fetch(:track),
            chart: derived.fetch(:chart),
            route_metadata: derived.fetch(:route_metadata),
            at: @now
          )
          @attachment
        rescue StandardError
          blob&.purge
          raise
        end
      end

      private

      # Remote GPX carries geometry and, from Allure, no timestamps at all.
      # Distances are geodesic between adjacent points; elapsed time is only
      # present for peers that do include `<time>`.
      def derive
        time_base = 0
        built = @verified.track.segments.map do |segment|
          result = build_segment(segment, time_base)
          time_base += result.fetch(:duration)
          result
        end

        coordinates = built.map { |segment| segment.fetch(:coordinates) }
        track = Allure::Federation::Privacy::SanitizedTrackSerializer
          .new(filtered: FilteredValue.new(coordinates)).call
        chart = Allure::Gpx::ChartSeries.new(
          workout_started_at: EPOCH,
          segments: built.map { |segment| segment.fetch(:adapter) }
        ).call.map { |point| point.slice(:distance, :elapsed_time, :elevation) }

        {
          track:,
          chart:,
          route_metadata: {
            "bounds" => bounds(coordinates),
            "segments_count" => built.length
          }
        }
      end

      def build_segment(segment, time_base)
        points = segment.points
        cumulative = 0.0
        previous = nil
        serialized = points.map do |point|
          cumulative += previous ? Allure::Gpx::Geo.distance(previous, point) : 0.0
          previous = point
          Allure::Gpx::PointSerializer.serialize(
            time_offset_seconds: elapsed_within(points.first, point),
            cumulative_distance_metres: cumulative,
            latitude: point.latitude,
            longitude: point.longitude,
            elevation: point.elevation,
            heart_rate: point.heart_rate,
            cadence: point.cadence,
            power: point.power
          )
        end

        {
          coordinates: points.map { |point| [ point.longitude, point.latitude ] },
          duration: segment_duration(points),
          adapter: SegmentAdapter.new(
            started_at: EPOCH + time_base,
            points: serialized,
            distance: cumulative
          )
        }
      end

      def elapsed_within(first_point, point)
        return if first_point.time.nil? || point.time.nil?

        (point.time - first_point.time).round
      end

      def segment_duration(points)
        elapsed_within(points.first, points.last) || 0
      end

      def bounds(coordinates)
        points = coordinates.flatten(1)
        [
          points.map(&:first).min,
          points.map(&:last).min,
          points.map(&:first).max,
          points.map(&:last).max
        ]
      end
    end
  end
end
