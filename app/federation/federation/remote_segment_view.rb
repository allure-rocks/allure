# frozen_string_literal: true

module Federation
  # The presentation projection for a received course. It mirrors the duck type
  # of Workouts::PublicationView so the established metric and map partials
  # render it unchanged. The remote sport slug is matched to the shared seeded
  # catalog; an all-sports or unknown course keeps a neutral fallback
  # (docs/dev/SEGMENTS-FEDERATION.md).
  class RemoteSegmentView
    METRIC_KEYS = PublishingProfile::METRIC_KEYS
    MEDIA_STATUSES = %w[pending fetching].freeze
    SportFallback = RemoteNoteView::SportFallback

    attr_reader :segment, :name, :description, :content_html, :sport_label

    def initialize(segment)
      @segment = segment
      @representation = segment.representation.stringify_keys
      @name = @representation["name"].presence || segment.name
      @description = segment.description
      @content_html = segment.content_html
      @sport_label = segment.sport_label
    end

    def sport
      @sport ||= begin
        match = Sport.find_by(slug: @representation["sport_slug"]) if @representation["sport_slug"].present?
        match || SportFallback.new(label: fallback_label)
      end
    end

    def all_sports?
      @representation["sport_slug"].blank? && @sport_label.blank?
    end

    def average_grade = @representation["average_grade"]

    def metric_visible?(key) = @representation.key?(key.to_s)
    def metrics_present? = METRIC_KEYS.any? { |key| metric_visible?(key) }
    def points_count = nil

    def track = @representation["track"]
    def map_visible? = track.is_a?(Hash) && Array(track["features"]).any?

    def gpx_visible? = cached_attachment?("gpx")
    def route_image_visible? = route_image_attachment("light").present?

    def any_attachments? = segment.attachments.exists?
    def media_pending? = segment.attachments.where(status: MEDIA_STATUSES).exists?
    def media_cached? = gpx_visible? || route_image_visible?
    def media_unavailable? = any_attachments? && !media_pending? && !media_cached?

    # The copy action is offered only for a verified single-LineString course
    # whose GPX is already cached.
    def copyable? = gpx_visible? && single_line_string_track?

    # The cached route image closest to the requested theme, falling back to the
    # other variant so a themed URL never 404s while one variant is cached
    # (DESIGN.md §15.4).
    def route_image_attachment(theme)
      cached = segment.attachments.select do |attachment|
        attachment.kind == "route_image" && attachment.status == "cached" && attachment.blob.present?
      end
      requested, fallback = theme.to_s == "dark" ? %w[dark light] : %w[light dark]
      cached.find { |attachment| attachment.theme == requested } ||
        cached.find { |attachment| attachment.theme == fallback }
    end

    def to_param = segment.id

    METRIC_KEYS.each do |key|
      define_method(key) { @representation[key] }
    end

    private

    def fallback_label
      return @sport_label if @sport_label.present?
      return I18n.t("segments.details.all_sports") if all_sports?

      I18n.t("remote_segments.unknown_sport")
    end

    def single_line_string_track?
      features = track.is_a?(Hash) ? track["features"] : nil
      return false unless features.is_a?(Array) && features.length == 1

      geometry = features.first["geometry"]
      geometry.is_a?(Hash) && geometry["type"] == "LineString" &&
        geometry["coordinates"].is_a?(Array) && geometry["coordinates"].length >= 2
    end

    def cached_attachment?(kind)
      segment.attachments.where(kind:, status: "cached").any? { |attachment| attachment.blob.present? }
    end
  end
end
