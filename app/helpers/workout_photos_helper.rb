# frozen_string_literal: true

# Owner-only photo presentation (docs/dev/PHOTOS.md).
module WorkoutPhotosHelper
  # The two Turbo Frames a photo mutation may answer (DESIGN.md §20.24): the
  # card's gallery on the workout page, and the manager's list on its own page.
  def photo_gallery_frame_id(workout) = "photos-#{workout.to_param}"
  def photo_manager_frame_id(workout) = "photo-manager-#{workout.to_param}"

  # The element that owns the upload controller (the workout card or the
  # manager's column) carries the intake limits and the drag handlers, so the
  # whole surface accepts a drop.
  def photo_upload_attributes(workout, frame_id:)
    tag.attributes(data: {
      controller: "photo-upload",
      action: "turbo:frame-render->photo-upload#frameRendered dragover->photo-upload#dragOver " \
              "dragleave->photo-upload#dragLeave drop->photo-upload#drop",
      photo_upload_url_value: workout_photos_path(workout),
      photo_upload_frame_value: frame_id,
      photo_upload_error_value: t("photos.errors.network"),
      photo_upload_max_bytes_value: Allure::Photos::Config::MAX_BYTES,
      photo_upload_max_value: Allure::Photos::Config::MAX_PER_WORKOUT,
      photo_upload_remaining_value: [ Allure::Photos::Config::MAX_PER_WORKOUT - workout.photos.count, 0 ].max,
      photo_upload_types_value: Allure::Photos::Config.content_types.to_json,
      photo_upload_too_large_value: t("photos.errors.too_large"),
      photo_upload_unsupported_value: t("photos.errors.unsupported_type"),
      photo_upload_too_many_value: t("photos.errors.too_many")
    })
  end
  # The placed photos the owner's map and profile draw: their own thumbnail
  # endpoint, never a storage URL, and the position the owner already owns.
  def workout_photo_markers(workout, photos = workout.photos.to_a)
    photos.each_with_index.filter_map do |photo, index|
      next unless photo.ready? && photo.placed?

      {
        "id" => photo.to_param,
        "lon" => photo.location.x,
        "lat" => photo.location.y,
        "distance" => photo.track_distance,
        "thumbnail" => workout_photo_path(workout, photo, variant: :thumbnail),
        "label" => workout_photo_label(photo, index)
      }
    end
  end

  def workout_photo_label(photo, index)
    photo.caption.presence || t("photos.alt", number: index + 1)
  end

  def workout_photo_placement_text(photo)
    key = photo.location_source
    return t("photos.placement.sources.#{key}") unless photo.placed?

    t("photos.placement.placed", source: t("photos.placement.sources.#{key}"),
                                 distance: format_distance(photo.track_distance, precision: 1))
  end

  # The lightbox's second line (DESIGN.md §10.22): when the photo was taken and
  # how far along the route it sits. Both are the owner's own data.
  def workout_photo_lightbox_meta(photo)
    parts = []
    parts << t("photos.captured_at", time: l(photo.taken_at_local, format: :photo)) if photo.taken_at_local.present?
    parts << t("photos.distance_from_start", distance: format_distance(photo.track_distance, precision: 1)) if photo.placed?
    parts.join(" · ").presence
  end

  # A reader's lightbox has no capture time: a publication never carries one.
  # It keeps the distance along the published route when the profile shared it.
  def publication_photo_lightbox_meta(photo)
    return if photo.distance.nil?

    t("photos.distance_from_start", distance: format_distance(photo.distance, precision: 1))
  end

  # Why an automatic placement left a ready photo off the route
  # (docs/dev/PHOTOS.md), in the owner's terms. Nil for a photo that is placed, processing or
  # failed; a photo with no clue at all says so.
  def workout_photo_unplaced_reason(photo, diagnosis)
    return unless photo.ready? && !photo.placed?

    parts = []
    if diagnosis&.exif_metres
      parts << t("photos.unplaced.exif_far", distance: format_distance(diagnosis.exif_metres, precision: 1))
    end
    if diagnosis&.before_start
      parts << t("photos.unplaced.before_start", duration: format_duration_human(diagnosis.before_start))
    end
    if diagnosis&.after_finish
      parts << t("photos.unplaced.after_finish", duration: format_duration_human(diagnosis.after_finish))
    end
    parts.any? ? t("photos.unplaced.summary", reasons: parts.to_sentence) : t("photos.unplaced.no_clue")
  end

  # The photos the publish form lists (docs/dev/PHOTOS.md): every ready
  # photo, the ones taken inside a privacy zone unchecked and flagged.
  def publication_photo_choices(workout)
    return [] unless Allure::Photos::Config.enabled?

    photos = workout.photos.ready.to_a
    return [] if photos.empty?

    zone_filter = Workouts::PublicationPhotoSelection.zone_filter_for(workout.user)
    photos.each_with_index.map do |photo, index|
      { photo:, label: workout_photo_label(photo, index), sensitive: Workouts::PublicationPhotoSelection.sensitive?(photo, zone_filter) }
    end
  end

  def publication_photo_label(photo, index)
    photo.caption.presence || t("photos.alt", number: index + 1)
  end

  def publication_photo_url(publication, photo, variant = :display)
    publication_photo_path(publication, photo.id, variant: variant == :thumbnail ? "thumbnail" : nil)
  end

  # A reader's map markers (docs/dev/PHOTOS.md): a shared distance names a
  # point of the published route itself, never a new coordinate.
  def publication_photo_markers(view)
    photos = view.photos.select(&:distance)
    return [] if photos.empty? || !view.map_visible?

    segments = Array(view.track&.fetch("features", nil)).map { it.dig("geometry", "coordinates") }
    route = Allure::Photos::RouteDistance.new(segments)
    view.photos.each_with_index.filter_map do |photo, index|
      vertex = photo.distance && route.at(photo.distance)
      next unless vertex

      {
        "id" => photo.id,
        "lon" => vertex.longitude,
        "lat" => vertex.latitude,
        "distance" => photo.distance,
        "thumbnail" => publication_photo_url(view.publication, photo, :thumbnail),
        "label" => publication_photo_label(photo, index)
      }
    end
  end

  FEED_PHOTOS = 3

  # The first shared photos of a feed card and how many there are.
  def feed_photo_strip(view)
    return { photos: [], total: 0 } unless view.respond_to?(:photos) && view.photos_visible?

    photos = view.photos
    shown = photos.first(FEED_PHOTOS).each_with_index.map do |photo, index|
      { thumbnail: publication_photo_url(view.publication, photo, :thumbnail), label: publication_photo_label(photo, index) }
    end
    { photos: shown, total: photos.size }
  end

  # Minutes, signed, for the camera-clock field.
  def workout_photo_offset_minutes(workout) = workout.photo_time_offset_seconds / 60
end
