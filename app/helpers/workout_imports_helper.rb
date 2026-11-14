# frozen_string_literal: true

module WorkoutImportsHelper
  BATCH_STATUS_STYLES = {
    "queued" => [ "bg-secondary-lt", "clock" ],
    "processing" => [ "bg-primary-lt", "loader" ],
    "completed" => [ "bg-success-lt", "check" ],
    "failed" => [ "bg-danger-lt", "x" ],
    "cancelled" => [ "bg-secondary-lt", nil ]
  }.freeze

  ENTRY_STATUS_STYLES = {
    "queued" => [ "bg-secondary-lt", "clock" ],
    "processing" => [ "bg-primary-lt", "loader" ],
    "imported" => [ "bg-success-lt", "check" ],
    "failed" => [ "bg-danger-lt", "x" ],
    "duplicate" => [ "bg-secondary-lt", nil ],
    "cancelled" => [ "bg-secondary-lt", nil ],
    "skipped" => [ "bg-secondary-lt", nil ]
  }.freeze

  def import_batch_status_badge(status)
    import_status_badge(status, "workouts.batch_import.status.labels", BATCH_STATUS_STYLES)
  end

  def import_entry_status_badge(status)
    import_status_badge(status, "workouts.batch_import.entries.labels", ENTRY_STATUS_STYLES)
  end

  # The reason an entry did not import: the translated skip reason of a remote
  # activity (neutral), or the failure message (PLAN_REMOTE_IMPORTS.md §8.3).
  def import_entry_detail(entry)
    return if entry.error_message.blank? && !entry.skipped?
    return tag.span(t("workouts.batch_import.entries.skip_reasons.#{entry.skip_reason}"), class: "text-secondary") if entry.skipped?

    tag.span(entry.error_message, class: "text-danger")
  end

  def import_batch_source_label(batch)
    t("workouts.batch_import.sources.#{batch.source}.label")
  end

  # What a batch does before its entries exist.
  def import_batch_discovery_text(batch)
    if batch.remote?
      t("workouts.batch_import.status.listing", provider: import_batch_source_label(batch))
    elsif batch.strava_archive?
      t("workouts.batch_import.status.reading_archive")
    else
      t("workouts.batch_import.status.scanning")
    end
  end

  # The equipment a Strava archive created (PLAN_STRAVA_ARCHIVE.md §5).
  def import_batch_created_equipment(entries)
    entries.filter_map { |entry| entry.metadata["created_equipment"] }.uniq
  end

  # The photos a Strava archive attached, could not find and refused
  # (PLAN_STRAVA_ARCHIVE.md §6ter), or nil when it listed none.
  def import_batch_photo_line(entries)
    counts = %w[photos photos_missing photos_refused].index_with do |key|
      entries.sum { |entry| entry.metadata[key].to_i }
    end
    return if counts.values.all?(&:zero?)

    parts = [ t("workouts.batch_import.status.photos_attached", count: counts["photos"]) ]
    parts << t("workouts.batch_import.status.photos_missing", count: counts["photos_missing"]) if counts["photos_missing"].positive?
    parts << t("workouts.batch_import.status.photos_refused", count: counts["photos_refused"]) if counts["photos_refused"].positive?
    parts.join(" · ")
  end

  def import_batch_notice_level(status)
    case status.to_s
    when "completed" then "success"
    when "failed" then "danger"
    else "warning"
    end
  end

  private

  def import_status_badge(status, scope, styles)
    classes, icon = styles.fetch(status.to_s, [ "bg-secondary-lt", nil ])
    label = t("#{scope}.#{status}")
    return tag.span(label, class: "badge #{classes}") unless icon

    tag.span(class: "badge #{classes}") do
      safe_join([ tag.i(class: "ti ti-#{icon} me-1"), label ])
    end
  end
end
