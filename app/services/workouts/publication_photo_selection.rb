# frozen_string_literal: true

module Workouts
  # Which photos a publication freezes, and what of each (PLAN_PHOTOS.md
  # §5.2). Pure decisions over the owner's rows; the copies are made by
  # PublicationCandidate.
  #
  # A photo is sensitive when its placement or its EXIF position lies inside
  # an active privacy zone. Without an explicit choice (`selected_ids: nil`:
  # automatic publishing, the API) every ready, non-sensitive photo is taken.
  # An explicit choice may include a sensitive photo only with the owner's
  # acknowledgement; it is then shared without any position.
  class PublicationPhotoSelection
    class Unacknowledged < StandardError; end

    Entry = Data.define(:photo, :caption, :distance)

    def self.sensitive?(photo, zone_filter)
      [ photo.location, photo.exif_location ].compact.any? { zone_filter.covered?([ it.x, it.y ]) }
    end

    def self.zone_filter_for(user)
      zones = user.privacy_zones.active.map(&:to_value)
      # The filter needs a route to construct; coverage checks ignore it.
      Allure::Federation::Privacy::ZoneFilter.new(segments: [ [ [ 0.0, 0.0 ], [ 0.0, 0.0 ] ] ], zones:)
    end

    def initialize(workout:, profile:, published_segments:, selected_ids: nil, acknowledged: false)
      @workout = workout
      @settings = profile.settings
      @published_segments = published_segments
      @selected_ids = selected_ids&.map(&:to_s)
      @acknowledged = acknowledged == true
    end

    def call
      return [] unless @settings["photos"] == true

      zone_filter = self.class.zone_filter_for(@workout.user)
      route = Allure::Photos::RouteDistance.new(@published_segments)
      candidates.filter_map do |photo|
        sensitive = self.class.sensitive?(photo, zone_filter)
        next if sensitive && @selected_ids.nil?
        raise Unacknowledged if sensitive && !@acknowledged

        Entry.new(photo:, caption: (photo.caption.presence if @settings["photo_captions"] == true),
                  distance: (shared_distance(photo, route) unless sensitive))
      end
    end

    private

    def candidates
      photos = @workout.photos.ready.to_a
      return photos if @selected_ids.nil?

      photos.select { @selected_ids.include?(it.to_param) }
    end

    def shared_distance(photo, route)
      return unless @settings["photo_positions"] == true && photo.placed?

      route.snap(photo.location.x, photo.location.y)&.distance&.round(1)
    end
  end
end
