# frozen_string_literal: true

module Workouts
  # Applies `Allure::Photos::Placement` to a workout's photos (PLAN_PHOTOS.md
  # §4). Automatic placements (`exif`, `time`, `none`) are recomputed whenever
  # the photo, the camera offset or the recording changes; the owner's own
  # choices (`manual`, `cleared`) are never overwritten.
  class PhotoPlacement
    AUTOMATIC_SOURCES = %w[exif time none].freeze
    FACTORY = RGeo::Geographic.spherical_factory(srid: 4326)

    def initialize(workout:)
      @workout = workout
    end

    def refresh_all
      @workout.photos.ready.where(location_source: AUTOMATIC_SOURCES).find_each { refresh(it) }
    end

    def refresh(photo)
      return unless photo.ready? && AUTOMATIC_SOURCES.include?(photo.location_source)

      exif = photo.exif_location
      # A point read back from the database may be Cartesian: x and y are the
      # longitude and latitude on every factory.
      result = placement&.automatic(exif_longitude: exif&.x, exif_latitude: exif&.y,
                                    taken_at: capture_time(photo))
      apply(photo, result)
    end

    # Why an automatic placement found nothing, for the owner's page
    # (PLAN_PHOTOS.md §4). Nil for a photo that is placed, still processing, or
    # whose sources left no clue at all.
    def diagnose(photo)
      return unless photo.ready? && photo.location_source == "none"

      exif = photo.exif_location
      placement&.diagnose(exif_longitude: exif&.x, exif_latitude: exif&.y, taken_at: capture_time(photo))
    end

    # Answers false when the point is too far from the track to mean it.
    def place(photo, longitude:, latitude:)
      result = placement&.snap(longitude, latitude)
      return false unless result

      apply(photo, result)
      true
    end

    def clear(photo)
      photo.update!(location: nil, location_source: "cleared", track_distance: nil, track_elapsed: nil)
    end

    def automatic(photo)
      photo.update!(location: nil, location_source: "none", track_distance: nil, track_elapsed: nil)
      refresh(photo)
    end

    # The instant the photo was taken: its own offset when the file states
    # one, otherwise the wall clock read in the account's time zone; then the
    # owner's camera-clock correction.
    def capture_time(photo)
      local = photo.taken_at_local
      return if local.nil?

      instant = if photo.taken_at_utc_offset
        local - photo.taken_at_utc_offset
      else
        zone = ActiveSupport::TimeZone[@workout.user.time_zone] || Time.zone
        zone.local(local.year, local.month, local.day, local.hour, local.min, local.sec)
      end
      instant + @workout.photo_time_offset_seconds
    end

    private

    def placement
      return @placement if defined?(@placement)

      segments = @workout.positioned? ? @workout.track_segments.map { { started_at: it.started_at, points: it.points } } : []
      @placement = segments.any? ? Allure::Photos::Placement.new(segments:, started_at: @workout.started_at) : nil
      @placement = nil unless @placement&.positioned?
      @placement
    end

    def apply(photo, result)
      if result.nil?
        photo.update!(location: nil, location_source: "none", track_distance: nil, track_elapsed: nil)
      else
        photo.update!(location: FACTORY.point(result.longitude, result.latitude), location_source: result.source,
                      track_distance: [ result.distance, 0.0 ].max, track_elapsed: result.elapsed)
      end
    end
  end
end
