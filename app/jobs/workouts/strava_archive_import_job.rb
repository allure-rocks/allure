# frozen_string_literal: true

require "digest"

module Workouts
  # Imports a Strava archive (docs/dev/STRAVA-ARCHIVE.md). Discovery reads
  # `activities.csv` once and freezes one entry per activity — its name, type,
  # texts, commute flag and gear in the entry's metadata — then one per track
  # file the CSV does not name. Each entry then imports its original file
  # through `Workouts::Importer` with what the athlete wrote on Strava; an
  # activity without a file becomes a manual entry. A retry resumes at the
  # first unfinished entry; one archive runs at a time per account, so two
  # never create the same equipment.
  class StravaArchiveImportJob < ApplicationJob
    NEAR_DUPLICATE_WINDOW = 120.seconds
    TITLE_LENGTH = 255
    DESCRIPTION_LENGTH = 10_000
    NOTES_LENGTH = 500

    queue_as :default

    limits_concurrency key: ->(batch) { batch.user_id.to_s }, group: "StravaArchiveImport", duration: 12.hours

    retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 5

    def perform(batch)
      return if batch.terminal?

      I18n.with_locale(batch.user.locale) do
        batch.update!(status: "processing", started_at: batch.started_at || Time.current)
        batch.source_files.attachments.first&.blob&.open do |file|
          StravaArchiveReader.open(file) do |reader|
            discover(batch, reader) unless batch.discovered_at
            process_entries(batch, reader)
          end
        end
        finish_batch(batch)
        batch.release_sources!
      rescue ArchiveReader::Error => error
        fail_batch(batch, error)
      rescue StandardError => error
        fail_batch(batch, error)
        raise
      end
    end

    private

    def discover(batch, reader)
      activities = reader.activities
      named = activities.filter_map(&:filename).to_set
      position = batch.entries.maximum(:position)&.next || 0

      activities.each do |activity|
        batch.entries.create_or_find_by!(source_key: "strava:#{activity.id}") do |entry|
          entry.position = position
          entry.source_name = (activity.name.presence ||
                               I18n.t("workouts.batch_import.remote.untitled", id: activity.id)).truncate(TITLE_LENGTH)
          entry.source_path = activity.filename
          entry.external_id = activity.id
          entry.metadata = activity_metadata(activity)
          entry.status = "queued"
        end
        position += 1
      end
      reader.activity_files.reject { |name| named.include?(name) }.each do |name|
        batch.entries.create_or_find_by!(source_key: "strava-file:#{name}") do |entry|
          entry.position = position
          entry.source_name = File.basename(name)
          entry.source_path = name
          entry.metadata = { "filename" => name }
          entry.status = "queued"
        end
        position += 1
      end
      batch.update!(discovered_at: Time.current)
      batch.refresh_progress!
    end

    def activity_metadata(activity)
      {
        "strava_id" => activity.id,
        "date" => activity.date,
        "name" => activity.name,
        "type" => activity.type_label,
        "description" => activity.description,
        "private_note" => activity.private_note,
        "commute" => activity.commute,
        "gear" => activity.gear_name,
        "filename" => activity.filename,
        # Only an activity without a file is built from its figures (slice 2).
        "figures" => (activity.figures unless activity.file?),
        "media" => activity.media.presence
      }.compact
    end

    def process_entries(batch, reader)
      gear = StravaArchiveGear.new(user: batch.user, items: reader.gear)
      @captions = Allure::Photos::Config.enabled? ? reader.media_captions : {}
      # An archive is history: whatever its entries enqueue — enrichments,
      # photo processing, webhooks — runs behind new outings (BacklogPriority).
      BacklogPriority.enqueue do
        batch.entries.where(status: %w[queued processing]).order(:position).each do |entry|
          break if batch.reload.cancellation_requested?

          process_entry(batch, reader, gear, entry)
        end
      end
    end

    def process_entry(batch, reader, gear, entry)
      # An entry left `processing` by an interrupted run may meet the workout
      # it created as a duplicate (Workouts::ImportResumption).
      @resumed = entry.status == "processing"
      entry.update!(status: "processing", started_at: entry.started_at || Time.current, error_message: nil)
      metadata = entry.metadata
      return import_manual(batch, reader, gear, entry) if metadata["filename"].blank?

      found = reader.extract(metadata["filename"]) { |member| import_member(batch, reader, gear, entry, member) }
      skip_entry(entry, "no_file") unless found
    rescue StandardError => error
      fail_entry(entry, error.message)
    ensure
      batch.refresh_progress! unless batch.terminal?
    end

    def import_member(batch, reader, gear, entry, member)
      digest = digest_io(member.io)
      entry.update_columns(source_digest: digest)
      metadata = entry.metadata
      declared_sport = declared_sport(metadata["type"])
      if (existing = batch.user.workouts.find_by(source_digest: digest))
        return finish_duplicate(batch, reader, entry, existing, declared: declared_sport)
      end

      equipment = gear.match(metadata["gear"], sport: declared_sport)

      result = Workouts::Importer.new(
        user: batch.user,
        uploaded_file: member.io,
        sport: batch.sport,
        declared_sport:,
        title: metadata["name"]&.truncate(TITLE_LENGTH),
        description: metadata["description"]&.truncate(DESCRIPTION_LENGTH),
        notes: metadata["private_note"]&.truncate(NOTES_LENGTH),
        commute: metadata["commute"] == true,
        equipment_ids: equipment && [ equipment.id ],
        filename: member.name,
        source_digest: digest,
        near_duplicate_window: NEAR_DUPLICATE_WINDOW,
        # An archive is a history, never a new outing (docs/dev/AUTO-PUBLISHING.md).
        bulk: true
      ).call

      record_created_equipment(entry, equipment)
      if result.success?
        finish_entry(entry, status: "imported", workout: result.workout, sport_source: result.sport_source)
        attach_photos(batch, reader, entry, result.workout)
      elsif result.duplicate?
        finish_duplicate(batch, reader, entry, result.workout || batch.user.workouts.find_by(source_digest: digest),
                         declared: declared_sport)
      elsif result.errors == [ I18n.t("workouts.import.errors.missing_sport") ]
        skip_entry(entry, "unsupported_sport")
      else
        fail_entry(entry, result.errors.join(", "))
      end
    end

    # An activity typed in by hand on Strava (slice 2): its sport must be
    # named, and an entry already starting within the window is the same one,
    # imported before.
    def import_manual(batch, reader, gear, entry)
      metadata = entry.metadata
      declared = declared_sport(metadata["type"])
      sport = declared || batch.sport
      return skip_entry(entry, "unsupported_sport") unless sport

      sport = batch.user.preferred_sport_for(sport.slug) || sport if declared
      equipment = gear.match(metadata["gear"], sport:)
      manual = StravaArchiveManualEntry.new(user: batch.user, metadata:, sport:,
                                            equipment_ids: equipment && [ equipment.id ])
      if (existing = near_entry(batch.user, manual.started_at))
        return finish_duplicate(batch, reader, entry, existing, declared:, fallback: !declared)
      end

      result = manual.call
      record_created_equipment(entry, equipment)
      if result.success?
        finish_entry(entry, status: "imported", workout: result.workout, sport_source: declared ? "declared" : "fallback")
        attach_photos(batch, reader, entry, result.workout)
      else
        fail_entry(entry, result.workout.errors.full_messages.join(", "))
      end
    rescue StravaArchiveManualEntry::Unreadable => error
      fail_entry(entry, error.message)
    end

    # The activity's photos (slice 3), only on a workout this entry created
    # and while photos are on, each with its `media.csv` caption.
    # `Workouts::PhotoUpload` checks each one — type, size, the per-workout
    # count, the account's quota —; a photo the archive lacks (Strava lists
    # some it does not ship) or a refused one is counted on the entry and
    # never fails it.
    def attach_photos(batch, reader, entry, workout)
      names = Array(entry.metadata["media"])
      # A workout that already holds photos got them from an earlier run of
      # this entry; attaching again would double them.
      return if names.empty? || !Allure::Photos::Config.enabled? || workout.photos.exists?

      upload = PhotoUpload.new(user: batch.user, workout:)
      counts = Hash.new(0)
      names.each do |name|
        found = reader.extract_media(name) do |io|
          photo = upload.call(io)
          caption = @captions.to_h[name]
          photo.update(caption: caption.truncate(Allure::Photos::Config::MAX_CAPTION)) if caption
          counts["photos"] += 1
        end
        counts["photos_missing"] += 1 unless found
      rescue PhotoUpload::Invalid, ArchiveReader::Error
        counts["photos_refused"] += 1
      end
      entry.update_columns(metadata: entry.metadata.merge(counts))
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, entry_id: entry.id })
    end

    # The workout this very entry created before an interruption is imported,
    # with its photos, not a duplicate of itself (Workouts::ImportResumption).
    # Its provenance is known from the row again; a detected sport is not.
    def finish_duplicate(batch, reader, entry, workout, declared:, fallback: false)
      unless ImportResumption.claims?(entry:, workout:, resumed: @resumed)
        return finish_entry(entry, status: "duplicate", workout:)
      end

      sport_source = if declared then "declared" elsif fallback then "fallback" end
      finish_entry(entry, status: "imported", workout:, sport_source:)
      attach_photos(batch, reader, entry, workout)
    end

    def near_entry(user, started_at)
      user.workouts.authored
        .where(started_at: (started_at - NEAR_DUPLICATE_WINDOW)..(started_at + NEAR_DUPLICATE_WINDOW))
        .min_by { |workout| (workout.started_at - started_at).abs }
    end

    def record_created_equipment(entry, equipment)
      return unless equipment&.created_label

      entry.update_columns(metadata: entry.metadata.merge("created_equipment" => equipment.created_label))
    end

    def declared_sport(label)
      slug = Allure::StravaArchive::ActivityTypes.slug_for(label)
      slug && Sport.active.find_by(slug:)
    end

    def digest_io(io)
      io.rewind
      digest = Digest::SHA256.new
      while (chunk = io.read(64 * 1024))
        digest.update(chunk)
      end
      io.rewind
      digest.hexdigest
    end

    def finish_entry(entry, status:, workout: nil, sport_source: nil)
      attributes = { status:, workout:, completed_at: Time.current }
      attributes[:sport_source] = sport_source if sport_source
      entry.update!(attributes)
    end

    def skip_entry(entry, reason)
      entry.update!(status: "skipped", skip_reason: reason, completed_at: Time.current)
    end

    def fail_entry(entry, message)
      entry.update!(status: "failed", error_message: message.to_s, completed_at: Time.current)
    end

    def finish_batch(batch)
      batch.reload
      open = batch.entries.where(status: %w[queued processing])
      if batch.cancellation_requested?
        open.update_all(status: "cancelled", completed_at: Time.current, updated_at: Time.current)
        batch.refresh_progress!
        batch.update!(status: "cancelled", completed_at: Time.current)
      elsif batch.entries.none?
        batch.update!(status: "failed", error_message: I18n.t("workouts.batch_import.errors.no_track_entries"),
                      completed_at: Time.current)
      else
        open.update_all(status: "failed", error_message: I18n.t("workouts.batch_import.errors.unfinished_entry"),
                        completed_at: Time.current, updated_at: Time.current)
        batch.refresh_progress!
        batch.update!(status: "completed", completed_at: Time.current)
      end
      enqueue_route_suggestion_sweep(batch)
      announce(batch)
    end

    # The archive skipped the per-recording route-suggestion pass; the account
    # sweep now walks its recordings newest first (docs/dev/SEGMENTS.md).
    def enqueue_route_suggestion_sweep(batch)
      return unless batch.status == "completed"
      return if batch.user.deactivated?

      Segments::RouteSuggestionSweepJob.set(priority: BacklogPriority::PRIORITY).perform_later(batch.user_id)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, batch_id: batch.id })
    end

    # The account hears by mail when its archive is done or failed; a
    # cancellation is its own doing and is not announced.
    def announce(batch)
      return unless %w[completed failed].include?(batch.status)
      return if batch.user.deactivated?

      ImportMailer.strava_archive_finished(batch).deliver_later
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, batch_id: batch.id })
    end

    def fail_batch(batch, error)
      return batch.release_sources! if batch.reload.terminal?

      batch.entries.where(status: %w[queued processing]).update_all(
        status: "failed", error_message: error.message, completed_at: Time.current, updated_at: Time.current
      )
      batch.refresh_progress!
      batch.update_columns(status: "failed", error_message: error.message, completed_at: Time.current,
                           updated_at: Time.current)
      batch.release_sources!
      announce(batch)
    end
  end
end
