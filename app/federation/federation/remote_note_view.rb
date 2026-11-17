# frozen_string_literal: true

module Federation
  # The presentation projection for a received note. It mirrors the duck type
  # of Workouts::PublicationView so the established metric, map, and chart
  # partials can render it unchanged. The remote sport label is matched to the
  # shared seeded catalog; an unknown label keeps the label and gets a neutral
  # route glyph (docs/dev/FEDERATION.md).
  class RemoteNoteView
    METRIC_KEYS = PublishingProfile::METRIC_KEYS
    MEDIA_STATUSES = %w[pending fetching].freeze

    SportFallback = Data.define(:label) do
      def slug = "remote"
      def colour_group = "other"
      def icon = Allure::SportPalette.icon_for(slug, colour_group)
      def translated_name = label
      def pace_speed_display = "speed"
      def pace_basis_metres = nil
      def pace_basis? = false
      # An unknown remote sport is never assumed to lead with power.
      def power_led? = false
      def cadence_unit = nil
    end

    attr_reader :note, :title, :description, :content_html, :started_at, :metrics, :sport_label

    # `sport_catalog` (a Sport::Catalog) lets a list match the remote label
    # without one query per note.
    def initialize(note, sport_catalog: nil)
      @note = note
      @sport_catalog = sport_catalog
      @representation = note.representation.stringify_keys
      @metrics = @representation.fetch("metrics", {}).stringify_keys
      @sport_label = note.sport_label
      @title = note.title.presence || @sport_label.presence || I18n.t("remote_notes.untitled")
      @description = note.description
      @content_html = note.content_html
      @started_at = note.started_at
    end

    def sport
      @sport ||= begin
        label = @sport_label.to_s.strip
        match = if label.blank?
          nil
        elsif @sport_catalog
          @sport_catalog.find_label(label)
        else
          Sport.find_by("LOWER(label) = ?", label.downcase)
        end
        match || SportFallback.new(label: label.presence || I18n.t("remote_notes.unknown_sport"))
      end
    end

    def metric_visible?(key) = @metrics.key?(key.to_s)
    def metrics_present? = @metrics.any?
    def points_count = nil

    def record_types = Array(@representation["record_types"])
    def record_distances = Array(@representation["record_distances"])

    def device = @representation["device"]

    def commute = @representation["commute"] == true

    def weather = (@representation["weather"] if @representation["weather"].is_a?(Hash))

    def comments_closed? = @representation["comments_closed"] == true

    def track = @representation["track"]
    def chart = @representation["chart"]
    def map_visible? = track.is_a?(Hash) && Array(track["features"]).any?
    def chart_visible? = chart.is_a?(Array) && chart.any?

    def gpx_visible? = cached_attachment?("gpx")
    def route_image_visible? = route_image_attachment("light").present?

    def any_attachments? = attachments.any?
    def media_pending? = attachments.any? { |attachment| MEDIA_STATUSES.include?(attachment.status) }
    def media_cached? = gpx_visible? || route_image_visible?
    def media_unavailable? = any_attachments? && !media_pending? && !media_cached?

    # The route-image states a feed card renders (DESIGN.md §8.3), scoped to
    # that one attachment: a note that declared only a GPX shows no image
    # skeleton and no unavailable frame. A note that declared both variants is
    # cached as soon as either arrives.
    def route_image_pending?
      attachments.any? { |attachment| attachment.kind == "route_image" && MEDIA_STATUSES.include?(attachment.status) }
    end

    def route_image_unavailable?
      attachments.any? { |attachment| attachment.kind == "route_image" } &&
        !route_image_pending? && !route_image_visible?
    end

    # The cached route image closest to the requested theme, falling back to the
    # other variant so a themed URL never 404s while one variant is cached
    # (DESIGN.md §15.4).
    def route_image_attachment(theme)
      cached = attachments.select do |attachment|
        attachment.kind == "route_image" && attachment.status == "cached" && attachment.blob.present?
      end
      requested, fallback = theme.to_s == "dark" ? %w[dark light] : %w[light dark]
      cached.find { |attachment| attachment.theme == requested } ||
        cached.find { |attachment| attachment.theme == fallback }
    end

    def to_param = note.id

    METRIC_KEYS.each do |key|
      define_method(key) { @metrics[key] }
    end

    private

    # Read through the association so a preloaded `attachments: :blob` serves
    # every predicate without a query per note.
    def attachments = @attachments ||= note.attachments.to_a

    def cached_attachment?(kind)
      attachments.any? { |attachment| attachment.kind == kind && attachment.status == "cached" && attachment.blob.present? }
    end
  end
end
