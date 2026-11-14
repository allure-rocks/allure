# frozen_string_literal: true

require "digest"

module Workouts
  class ImportBatchJob < ApplicationJob
    queue_as :default

    # One file import at a time per account: its others wait their turn
    # instead of taking every worker thread (PLAN_IMPORT_SOURCES.md §3.2).
    limits_concurrency key: ->(batch) { batch.user_id.to_s }, group: "WorkoutImportBatch", duration: 6.hours

    retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 5

    # `time_shift:` is the optional offset in seconds the demo seed passes
    # through to each import (PLAN_DEMO.md §4); ordinary batches never set it.
    def perform(batch, time_shift: nil)
      return if batch.terminal?

      @time_shift = time_shift
      I18n.with_locale(batch.user.locale) do
        begin_batch(batch)
        discover_sources(batch)
        process_sources(batch)
        finish_batch(batch)
        batch.release_sources!
      rescue StandardError => error
        fail_batch(batch, error)
        raise
      end
    end

    private

    def begin_batch(batch)
      batch.update!(status: "processing", started_at: Time.current)
    end

    # Enumerates every source before importing anything so the batch carries
    # its real total from the first refresh. The progress bar must never read
    # "N of N" while files remain.
    def discover_sources(batch)
      return if batch.cancellation_requested?

      reader = Workouts::ArchiveReader.new
      batch.source_files.attachments.each do |attachment|
        break if batch.cancellation_requested?

        discover_source(batch, attachment, reader)
      end
    end

    def discover_source(batch, attachment, reader)
      source_name = attachment.blob.filename.to_s
      attachment.blob.open do |file|
        reader.each_manifest_entry(file, filename: source_name) do |manifest|
          batch.entries.create_or_find_by!(source_key: "#{attachment.id}:#{manifest.index}") do |record|
            record.position = next_position(batch)
            record.source_name = manifest.name
            record.source_path = manifest.name == source_name ? nil : manifest.name
            record.status = "queued"
          end
        end
      end
    rescue StandardError => error
      fail_discovered_source(batch, attachment, error)
    ensure
      batch.refresh_progress! unless batch.terminal?
    end

    # One broken source never takes the batch down: its discovered rows are
    # dropped and replaced by a single failed entry, so the frozen total stays
    # exact and later sources still import.
    def fail_discovered_source(batch, attachment, error)
      discard_queued_source_entries(batch, attachment.id)
      return if source_entries(batch, attachment.id).exists? || batch.entries.exists?(source_key: "source:#{attachment.id}")

      fail_entry(
        batch,
        source_key: "source:#{attachment.id}",
        source_name: attachment.blob.filename.to_s,
        source_path: nil,
        error: error.message
      )
    end

    def process_sources(batch)
      return if batch.cancellation_requested?

      reader = Workouts::ArchiveReader.new
      batch.source_files.attachments.each do |attachment|
        break if batch.cancellation_requested?
        next if batch.entries.exists?(source_key: "source:#{attachment.id}")

        process_source(batch, attachment, reader)
      end
    end

    def process_source(batch, attachment, reader)
      source_name = attachment.blob.filename.to_s
      attachment.blob.open do |file|
        reader.each_entry(file, filename: source_name) do |archive_entry|
          process_entry(batch, attachment.id, source_name, archive_entry)
          break if batch.cancellation_requested?
        end
      end
    rescue Workouts::ArchiveReader::Error => error
      fail_source_entries(batch, attachment, error)
    ensure
      batch.refresh_progress! unless batch.terminal?
    end

    def process_entry(batch, attachment_id, source_name, archive_entry)
      source_key = "#{attachment_id}:#{archive_entry.index}"
      source_path = archive_entry.name == source_name ? nil : archive_entry.name
      entry = batch.entries.find_or_create_by!(source_key:) do |record|
        record.position = next_position(batch)
        record.source_name = archive_entry.name
        record.source_path = source_path
      end
      return if entry.terminal?

      if batch.cancellation_requested?
        cancel_entry(entry)
        return
      end

      resumed = entry.status == "processing"
      entry.update!(
        source_name: archive_entry.name,
        source_path: source_path,
        status: "processing",
        started_at: entry.started_at || Time.current,
        error_message: nil
      )
      digest = digest_io(archive_entry.io)
      entry.update_column(:source_digest, digest)

      existing_workout = batch.user.workouts.find_by(source_digest: digest)
      if existing_workout
        finish_duplicate(entry, existing_workout, resumed:)
        return
      end

      result = Workouts::Importer.new(
        user: batch.user,
        uploaded_file: archive_entry.io,
        sport: batch.sport,
        # The options card's title belongs to the single workout a single-file
        # import produces; a batch never titles every entry alike
        # (PLAN_IMPORT_SOURCES.md §2).
        title: single_entry_batch?(batch) ? batch.title : nil,
        notes: batch.notes,
        commute: batch.commute,
        equipment_ids: batch.equipment_ids,
        filename: archive_entry.name,
        source_digest: digest,
        bulk: bulk?(batch),
        time_shift: @time_shift
      ).call

      if result.success?
        finish_entry(
          entry,
          status: "imported",
          workout: result.workout,
          sport_source: result.sport_source
        )
      elsif result.duplicate?
        finish_duplicate(entry, result.workout || batch.user.workouts.find_by(source_digest: digest), resumed:)
      else
        finish_entry(entry, status: "failed", error_message: result.errors.join(", "))
      end
    rescue StandardError => error
      if entry
        fail_entry_record(entry, error.message)
      else
        fail_entry(
          batch,
          source_key:,
          source_name: archive_entry.name,
          source_path:,
          error: error.message
        )
      end
    ensure
      batch.refresh_progress! unless batch.terminal?
    end

    # Every source is enumerated before the first import, so the frozen total
    # already tells an archive from a few new outings (PLAN_AUTO_PUBLISHING.md
    # §3).
    def bulk?(batch)
      batch.total_entries > WorkoutAutoPublication::BULK_FILE_ENTRIES
    end

    def single_entry_batch?(batch)
      batch.total_entries == 1
    end

    def digest_io(io)
      io.rewind if io.respond_to?(:rewind)
      digest = Digest::SHA256.new
      while (chunk = io.read(64 * 1024))
        digest.update(chunk)
      end
      io.rewind if io.respond_to?(:rewind)
      digest.hexdigest
    end

    # The workout this very entry created before an interruption is imported,
    # not a duplicate of itself (Workouts::ImportResumption).
    def finish_duplicate(entry, workout, resumed:)
      status = ImportResumption.claims?(entry:, workout:, resumed:) ? "imported" : "duplicate"
      finish_entry(entry, status:, workout:)
    end

    def finish_entry(entry, status:, workout: nil, error_message: nil, sport_source: nil)
      attributes = {
        status:,
        workout:,
        error_message:,
        completed_at: Time.current
      }
      attributes[:sport_source] = sport_source if sport_source
      entry.update!(attributes)
    end

    def fail_entry(batch, source_key:, source_name:, source_path:, error:)
      entry = batch.entries.find_or_create_by!(source_key:) do |record|
        record.position = next_position(batch)
        record.source_name = source_name
        record.source_path = source_path
      end
      fail_entry_record(entry, error)
    end

    def fail_entry_record(entry, error)
      entry.update!(status: "failed", error_message: error.to_s, completed_at: Time.current)
    end

    def cancel_entry(entry)
      entry.update!(status: "cancelled", completed_at: Time.current)
    end

    # A source that fails after discovery keeps its frozen total: members that
    # were never reached are failed with the archive error instead of quietly
    # disappearing from the count.
    def fail_source_entries(batch, attachment, error)
      scope = source_entries(batch, attachment.id)
      fail_entries(scope.where.not(status: WorkoutImportEntry::TERMINAL_STATUSES), error.message)
      return if scope.exists?

      fail_entry(
        batch,
        source_key: "source:#{attachment.id}",
        source_name: attachment.blob.filename.to_s,
        source_path: nil,
        error: error.message
      )
    end

    def source_entries(batch, attachment_id)
      batch.entries.where("source_key LIKE ?", "#{attachment_id}:%")
    end

    def discard_queued_source_entries(batch, attachment_id)
      source_entries(batch, attachment_id).where(status: "queued").delete_all
    end

    def fail_entries(scope, message)
      scope.update_all(
        status: "failed",
        error_message: message,
        completed_at: Time.current,
        updated_at: Time.current
      )
    end

    def next_position(batch)
      batch.entries.maximum(:position)&.next || 0
    end

    def finish_batch(batch)
      if batch.cancellation_requested?
        cancel_remaining_entries(batch)
        batch.refresh_progress!
        batch.update!(status: "cancelled", completed_at: Time.current)
      elsif batch.entries.none?
        batch.update!(status: "failed", error_message: I18n.t("workouts.batch_import.errors.no_track_entries"), completed_at: Time.current)
      else
        fail_remaining_entries(batch)
        batch.refresh_progress!
        batch.update!(status: "completed", completed_at: Time.current)
      end
      enqueue_route_suggestion_sweep(batch)
    end

    # A bulk import skipped the per-recording route-suggestion pass; the
    # account sweep now walks its recordings newest first (PLAN_SEGMENTS.md
    # §7.7). A failed or cancelled batch suggests nothing.
    def enqueue_route_suggestion_sweep(batch)
      return unless batch.status == "completed"
      return unless bulk?(batch)
      return if batch.user.deactivated?

      Segments::RouteSuggestionSweepJob.set(priority: BacklogPriority::PRIORITY).perform_later(batch.user_id)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, batch_id: batch.id })
    end

    def cancel_remaining_entries(batch)
      batch.entries.where(status: %w[queued processing]).update_all(
        status: "cancelled",
        completed_at: Time.current,
        updated_at: Time.current
      )
    end

    def fail_remaining_entries(batch)
      fail_entries(
        batch.entries.where(status: %w[queued processing]),
        I18n.t("workouts.batch_import.errors.unfinished_entry")
      )
    end

    def fail_batch(batch, error)
      unless batch.terminal?
        fail_entries(batch.entries.where(status: %w[queued processing]), error.message)
        batch.update_columns(
          status: "failed",
          error_message: error.message,
          completed_at: Time.current,
          updated_at: Time.current
        )
      end
      batch.release_sources!
    end
  end
end
