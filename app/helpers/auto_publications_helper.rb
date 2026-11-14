# frozen_string_literal: true

# The owner-facing wording of an automatic publication (PLAN_AUTO_PUBLISHING.md
# §7), shared by the import entries and the workout's sharing card.
module AutoPublicationsHelper
  def auto_publication_text(row)
    audience = t("publishing_profiles.audiences.#{row.audience}")
    case row.status
    when "waiting"
      t("auto_publications.status.waiting", audience:)
    when "published"
      publication = row.workout_publication
      if publication&.scheduled?
        t("auto_publications.status.scheduled", audience:, date: l(publication.scheduled_for, format: :long))
      else
        t("auto_publications.status.published", audience:)
      end
    else
      t("auto_publications.status.not_published", audience:, reason: auto_publication_reason(row))
    end
  end

  def auto_publication_reason(row)
    t("auto_publications.reasons.#{row.reason}",
      days: WorkoutAutoPublication::RECENT_WINDOW.in_days.to_i,
      files: WorkoutAutoPublication::BULK_FILE_ENTRIES,
      hours: (WorkoutAutoPublication::ENRICHMENT_DEADLINE / 1.hour).to_i)
  end

  def auto_publication_icon(row)
    case row.status
    when "waiting" then "hourglass"
    when "published" then "bolt"
    when "failed" then "alert-triangle"
    else "bolt-off"
    end
  end

  # The line under an imported entry: one sentence per audience.
  def import_entry_auto_publication(entry)
    return unless entry.status == "imported" && entry.workout

    rows = entry.workout.auto_publications.sort_by { |row| WorkoutPublication::AUDIENCE_PRECEDENCE.index(row.audience).to_i }
    return if rows.empty?

    safe_join(rows.map do |row|
      tag.div(class: "small #{row.failed? ? 'text-warning' : 'text-secondary'}") do
        safe_join([ tag.i(class: "ti ti-#{auto_publication_icon(row)} me-1", "aria-hidden": "true"), auto_publication_text(row) ])
      end
    end)
  end
end
