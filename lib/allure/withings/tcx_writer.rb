# frozen_string_literal: true

require "nokogiri"
require "time"

module Allure
  module Withings
    # Builds the deterministic TCX original of one Withings session
    # (docs/dev/REMOTE-IMPORTS.md, decisions 10 and 11). The same series
    # always build the same bytes, so the `(user_id, source_digest)` index
    # deduplicates a re-import.
    #
    # A positioned session writes one trackpoint per location sample with
    # the heart-rate sample nearest in time when one lies within
    # `MAX_HEART_RATE_DELTA_SECONDS` — a two-cursor linear merge, never a
    # rescan per point. An indoor session writes one trackpoint per
    # heart-rate sample without a `Position`: Allure's TCX parser opens a
    # positionless recording from those exactly as from a device's indoor
    # export (PLAN_NO_GPS.md §3). A session whose location answer carries
    # fewer than two samples falls back to the heart-rate timeline: one
    # fix is not a route, and no position a sample does not carry is ever
    # invented. No distance is interpolated either: the summary lap keeps
    # what Withings measured, nothing more.
    #
    # A location sample's row carries latitude, longitude and elevation in
    # metres (columns 0, 1 and 2, with `-20 000` as the no-elevation
    # sentinel; the columns beyond stay unexplained), so positioned
    # trackpoints keep their `<AltitudeMeters>` and the analysis gains an
    # elevation profile.
    class TcxWriter
      MAX_HEART_RATE_DELTA_SECONDS = 10
      LOCATION_ELEVATION_INDEX = 2
      ELEVATION_SENTINEL = -20_000.0
      TCX_NAMESPACE = "http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"
      XSI_NAMESPACE = "http://www.w3.org/2001/XMLSchema-instance"
      AUTHOR = "Withings"

      # The merged, time-ordered samples of one session.
      Point = Data.define(:time, :latitude, :longitude, :elevation, :heart_rate) do
        def positioned? = !latitude.nil? && !longitude.nil?
      end

      class << self
        # `activity` is a `Client::Activity`, `location` and `heart_rate`
        # the two `Client::Series`. Returns the TCX document as a String.
        def build(activity:, location:, heart_rate:)
          raise ArgumentError, "the session has no start" if activity.started_at.nil?

          positioned, timeline = merge(location:, heart_rate:)
          # One fix is not a route: a track needs two positions, and the
          # heart-rate timeline is the honest fallback (observed 2026-11-01:
          # a GPS session whose location answer carries a single sample).
          # No position a sample does not carry is ever invented.
          points = positioned.length >= 2 ? positioned : timeline
          if points.length < 2
            raise Error::NoSamples, "the session recorded fewer than two position or heart-rate samples"
          end

          started_at = activity.started_at.utc
          Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
            xml.TrainingCenterDatabase(xmlns: TCX_NAMESPACE, "xmlns:xsi": XSI_NAMESPACE) do
              xml.Activities do
                xml.Activity(Sport: SportMapping.sport_name(activity.category)) do
                  xml.Id started_at.iso8601
                  xml.Lap(StartTime: started_at.iso8601) do
                    xml.TotalTimeSeconds total_time(activity, points)
                    write_summary(xml, activity)
                    xml.TriggerMethod "Manual"
                    xml.Track do
                      points.each do |point|
                        xml.Trackpoint do
                          xml.Time point.time.utc.iso8601
                          if point.positioned?
                            xml.Position do
                              xml.LatitudeDegrees format("%.7f", point.latitude)
                              xml.LongitudeDegrees format("%.7f", point.longitude)
                            end
                            xml.AltitudeMeters format("%.1f", point.elevation) if point.elevation
                          end
                          if point.heart_rate
                            xml.HeartRateBpm do
                              xml.Value point.heart_rate
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end
              xml.Author("xsi:type": "Application_t") do
                xml.Name AUTHOR
              end
            end
          end.to_xml
        end

        private

        # The summary end when Withings measured one, otherwise the last
        # recorded sample — never an invented duration.
        def total_time(activity, points)
          ended_at = activity.ended_at || points.last.time
          (ended_at - activity.started_at).to_i
        end

        def write_summary(xml, activity)
          distance = summary_distance(activity)
          xml.DistanceMeters format("%.1f", distance) if distance
          calories = activity.data&.dig("calories")
          xml.Calories calories.to_f.round if calories.to_f.positive?
        end

        # `gps.distance` is the GPS-measured distance, `data.distance` the
        # watch's own (steps or sensor); neither is interpolated here.
        def summary_distance(activity)
          value = activity.gps&.dig("distance") || activity.data&.dig("distance")
          value&.to_f
        end

        # Returns the positioned candidates (one per location sample with the
        # nearest heart rate within the delta and the elevation column) and
        # the heart-rate timeline (one point per sample, without any
        # position), both time-ordered.
        def merge(location:, heart_rate:)
          rates = heart_rate_samples(heart_rate)
          cursor = 0
          positioned = []
          location.dates.each_with_index do |epoch, index|
            row = location.rows[index] || []
            next unless row.length >= 2

            cursor = nearest(rates, epoch, cursor)
            sample = rates[cursor]
            bpm = sample && (epoch - sample.first).abs <= MAX_HEART_RATE_DELTA_SECONDS ? sample.last : nil
            positioned << Point.new(
              time: Time.at(epoch).utc,
              latitude: row[0].to_f, longitude: row[1].to_f,
              elevation: sample_elevation(row), heart_rate: bpm
            )
          end
          timeline = rates.map { |epoch, bpm| Point.new(time: Time.at(epoch).utc, latitude: nil, longitude: nil, elevation: nil, heart_rate: bpm) }
          [ positioned.sort_by(&:time), timeline.sort_by(&:time) ]
        end

        # The row's third value is the elevation in metres; `-20 000` is
        # Withings's "no elevation" sentinel (observed 2026-11-01).
        def sample_elevation(row)
          return nil unless row.length > LOCATION_ELEVATION_INDEX

          value = row[LOCATION_ELEVATION_INDEX].to_f
          value <= ELEVATION_SENTINEL ? nil : value
        end

        def heart_rate_samples(series)
          series.dates.each_with_index.filter_map do |epoch, index|
            value = series.rows[index]&.first
            [ epoch.to_i, value.to_i ] if value.to_f.positive?
          end
        end

        # Advances the cursor while the next sample is at least as close to
        # the location sample's time — one linear pass over both series.
        def nearest(samples, epoch, cursor)
          while cursor + 1 < samples.length &&
                (samples[cursor + 1].first - epoch).abs <= (samples[cursor].first - epoch).abs
            cursor += 1
          end
          cursor
        end
      end
    end
  end
end
