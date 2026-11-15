# frozen_string_literal: true

module Workouts
  class PublicationView
    METRIC_KEYS = PublishingProfile::METRIC_KEYS

    attr_reader :sport, :user, :started_at, :title, :description, :metrics

    # `sport_catalog` (a Sport::Catalog) lets a list resolve the snapshot's
    # sport without one query per publication. `frozen:` is the owner-only
    # projection of a scheduled publication (docs/dev/DELAYED-PUBLISHING.md): the
    # policy still denies every reader, but the owner must review exactly what
    # was frozen before it activates, so resource visibility follows the
    # snapshot instead of the lifecycle status. Callers must have authorized
    # the owner first — the scheduled card is rendered only on the owner's page.
    def initialize(publication, principal: nil, sport_catalog: nil, frozen: false)
      @publication = publication
      @principal = principal || Workouts::PublicationPrincipal.anonymous
      @frozen = frozen
      @representation = publication.representation.stringify_keys
      @metrics = @representation.fetch("metrics", {}).stringify_keys
      slug = @representation.fetch("sport_slug")
      @sport = sport_catalog ? sport_catalog.fetch_slug!(slug) : Sport.find_by!(slug:)
      @user = publication.workout.user
      @started_at = Time.iso8601(@representation.fetch("started_at"))
      @title = @representation["title"]
      @description = @representation["description"]
    rescue ActiveRecord::RecordNotFound, ArgumentError, KeyError, NoMethodError, TypeError
      raise ActiveRecord::RecordNotFound
    end

    def to_param = @publication.workout.to_param

    def metric_visible?(key) = @metrics.key?(key.to_s)
    def metrics_present? = @metrics.any?
    def map_visible? = @frozen ? frozen_route? : publication_policy.allowed?(resource: :map)
    def route_image_visible? = @frozen ? frozen_route_image? : publication_policy.allowed?(resource: :route_image)
    def basemap_visible? = @publication.basemap_enabled?

    # The media states the feed card renders (DESIGN.md §8.3). A local
    # publication's image is either attached or still rendering; it never
    # fails for good, so "unavailable" is a remote-only state.
    def route_image_pending? = @publication.route_image_pending?
    def route_image_unavailable? = false

    def record_types = Array(@representation["record_types"])
    def record_distances = Array(@representation["record_distances"])

    def device = @representation["device"]

    def commute = @representation["commute"] == true

    def weather = (@representation["weather"] if @representation["weather"].is_a?(Hash))

    def comments_closed? = @representation["comments_closed"] == true

    # The frozen photos (PLAN_PHOTOS.md §5.4), each served by the
    # publication's own media endpoint, in their published order.
    PhotoItem = Data.define(:id, :width, :height, :caption, :distance)

    def photos_visible?
      return false unless Array(@representation["photos"]).any?

      @frozen ? @publication.profile_settings["photos"] == true : publication_policy.allowed?(resource: :photos)
    end

    def photos
      return [] unless photos_visible?

      Array(@representation["photos"]).map do |photo|
        PhotoItem.new(id: photo["id"], width: photo["width"], height: photo["height"],
                      caption: photo["caption"], distance: photo["distance"])
      end
    end

    def track = @representation["track"]
    def chart = @representation["chart"]
    def chart_visible? = @frozen ? frozen_chart? : publication_policy.allowed?(resource: :chart)
    def publication = @publication

    METRIC_KEYS.each do |key|
      define_method(key) { @metrics[key] }
    end

    def points_count = nil

    private

    def frozen_route?
      @publication.profile_settings["route"] == true && @publication.track.is_a?(Hash)
    end

    def frozen_chart?
      chart = @publication.representation["chart"]
      chart.is_a?(Array) && chart.any?
    end

    def frozen_route_image?
      @publication.profile_settings["route_image"] == true &&
        @publication.sanitized_attachment(:route_image).present?
    end

    def publication_policy
      @publication_policy ||= Workouts::PublicationPolicy.new(
        publication: @publication,
        principal: @principal
      )
    end
  end
end
