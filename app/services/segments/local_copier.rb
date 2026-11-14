# frozen_string_literal: true

module Segments
  # Copies another account's shared course into the copier's own private
  # segments, in the recorded direction or reversed, and creates the reversed
  # copy of the owner's own segment or route. The copy carries no new source
  # workout: its geometry, metrics and stored elevation profile are frozen
  # from the source — the owner's own copy keeps the source activity link —
  # and the model's create hooks render its route image and match the copier's
  # own workouts against it (a reversed copy only matches recordings made in
  # the opposite direction).
  class LocalCopier
    class CopyError < StandardError; end

    Result = Data.define(:segment)

    def initialize(user:, segment:, reversed: false)
      @user = user
      @source = segment
      @reversed = reversed
    end

    def call!
      Result.new(segment: @user.segments.create!(attributes))
    rescue ActiveRecord::RecordInvalid => error
      raise CopyError,
            I18n.t("segments.copy.errors.invalid", message: error.record.errors.full_messages.to_sentence)
    end

    private

    def attributes
      {
        name: copy_name,
        description: @source.description,
        kind: @source.kind,
        sport: @source.sport,
        visibility: "private",
        active: true,
        match_tolerance_meters: @source.match_tolerance_meters,
        matcher_version: Allure::Segments::Matcher::VERSION,
        source_workout: own_source_workout,
        source_start_index: nil,
        source_end_index: nil,
        geom: geometry,
        start_point: factory.point(*coordinates.first),
        end_point: factory.point(*coordinates.last),
        bounds: @source.bounds,
        distance: @source.distance,
        min_elevation: @source.min_elevation,
        max_elevation: @source.max_elevation,
        elevation_profile: copies_profile,
        elevation_source: @source.elevation_source,
        elevation_status: @source.elevation_source == "dem" ? "ready" : nil,
        signature: signature
      }.merge(elevation_attributes)
    end

    # Only the owner inherits the source activity link; another account's
    # source workout is never exposed to the copier. The stored indexes are
    # dropped either way: a reversed slice is not an ascending stream range.
    def own_source_workout
      return nil unless @source.user == @user

      @source.source_workout
    end

    def geometry
      factory.line_string(coordinates.map { |longitude, latitude| factory.point(longitude, latitude) })
    end

    def factory
      @factory ||= RGeo::Geographic.spherical_factory(srid: 4326)
    end

    def coordinates
      @coordinates ||= @source.geom.points.map { [ it.x, it.y ] }.then { @reversed ? it.reverse : it }
    end

    def signature
      return @source.signature unless @reversed

      Allure::Geometry::ShapeSignature.compute(coordinates)
    end

    def copies_profile
      return @source.elevation_profile unless @reversed

      Allure::Segments::ElevationProfile.reverse(@source.elevation_profile, distance: @source.distance)
    end

    # A reversed course climbs what the source descended, and its signed net
    # grade is the source's, negated.
    def elevation_attributes
      if @reversed
        { ascent: @source.descent, descent: @source.ascent, average_grade: @source.average_grade && -@source.average_grade }
      else
        { ascent: @source.ascent, descent: @source.descent, average_grade: @source.average_grade }
      end
    end

    def copy_name
      return @source.name unless @reversed

      I18n.t("segments.copy.reversed_name", name: @source.name).first(120)
    end
  end
end
