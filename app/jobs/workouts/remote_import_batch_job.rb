# frozen_string_literal: true

require "digest"

module Workouts
  # Imports the activities of a remote batch through its connection's
  # provider (docs/dev/REMOTE-IMPORTS.md). The same phases as the file
  # pipeline: discovery (the provider's listing, for a date-range batch),
  # then one entry at a time through `Workouts::Importer`.
  #
  # One batch runs at a time per connection. The provider's quota pauses the
  # batch and enqueues its continuation at the announced time; a transient
  # failure retries the job, which resumes at the first unfinished entry; a
  # refused token expires the connection and fails what remains.
  class RemoteImportBatchJob < ApplicationJob
    NEAR_DUPLICATE_WINDOW = 120.seconds
    MAX_ATTEMPTS = 5

    queue_as :remote_imports

    # One group for every job that spends a connection's tokens: Garmin rotates
    # the refresh token, so two concurrent refreshes would lose the link.
    limits_concurrency key: ->(batch, **) { batch.import_connection_id.to_s },
                       group: ImportConnection::CONCURRENCY_GROUP, duration: 2.hours

    retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 5
    retry_on Allure::RemoteImports::Error::Unavailable, wait: :polynomially_longer, attempts: MAX_ATTEMPTS do |job, error|
      job.give_up(job.arguments.first, error)
    end

    def perform(batch)
      return if batch.terminal?

      I18n.with_locale(batch.user.locale) do
        begin_batch(batch)
        connection = batch.import_connection
        unless connection&.usable?
          fail_open_entries(batch, I18n.t("workouts.batch_import.errors.connection_unusable"))
          finish_batch(batch)
          next
        end

        provider = ImportConnections::Providers.for(connection)
        discover(batch, connection, provider)
        process_entries(batch, connection, provider)
        finish_batch(batch)
      rescue Allure::RemoteImports::Error::RateLimited => error
        pause(batch, error.retry_at)
      rescue Allure::RemoteImports::Error::SessionEnded
        pause_for_reconnect(batch, connection)
      rescue Allure::RemoteImports::Error::AuthError
        expire(batch)
      rescue Allure::RemoteImports::Error::Unavailable
        raise
      rescue StandardError => error
        fail_batch(batch, error)
        raise
      end
    end

    # Called once the transient retries are spent.
    def give_up(batch, error)
      I18n.with_locale(batch.user.locale) do
        fail_open_entries(batch, I18n.t("workouts.batch_import.errors.provider_unavailable"))
        finish_batch(batch)
      end
    rescue StandardError
      fail_batch(batch, error)
    end

    private

    def begin_batch(batch)
      batch.update!(status: "processing", started_at: batch.started_at || Time.current, paused_until: nil)
    end

    def discover(batch, connection, provider)
      return if batch.discovered_at.present? || batch.cancellation_requested?

      if batch.range_from && batch.range_to
        zone = ActiveSupport::TimeZone[batch.user.time_zone] || Time.zone
        activities = provider.list(from: zone.local(batch.range_from.year, batch.range_from.month, batch.range_from.day),
                                   to: zone.local(batch.range_to.year, batch.range_to.month, batch.range_to.day).end_of_day)
        Workouts::RemoteImportEntries.new(batch:, connection:).add(activities)
      end
      batch.update!(discovered_at: Time.current)
    ensure
      batch.refresh_progress! unless batch.terminal?
    end

    def process_entries(batch, connection, provider)
      batch.entries.where(status: %w[queued processing]).order(:position).each do |entry|
        break if batch.reload.cancellation_requested?

        process_entry(batch, connection, provider, entry)
      end
    end

    def process_entry(batch, connection, provider, entry)
      resumed = entry.status == "processing"
      entry.update!(status: "processing", started_at: entry.started_at || Time.current, error_message: nil)
      activity = Allure::RemoteImports::RemoteActivity.from_metadata(entry.external_id, entry.metadata)

      if (known = connection.workouts.find_by(external_id: entry.external_id))
        finish_duplicate(entry, known, resumed:)
        # An interrupted run may have committed the workout before its photos:
        # the entry that created it attaches them now.
        attach_photos(batch, provider, entry, activity, known) if ImportResumption.claims?(entry:, workout: known, resumed:)
        return
      end

      # A manual activity has no file to fetch; an indoor one without a GPS
      # track does, and is imported positionlessly (docs/dev/NO-GPS.md).
      return skip_entry(entry, "no_file") if activity.manual
      # Positioned-only import (Withings fed by Apple Health, §7c.3): a
      # session without a route is skipped before any fetch.
      if connection&.positioned_only? && !activity.geometry
        return skip_entry(entry, "no_geometry")
      end
      if (near = near_duplicate(batch.user, activity.started_at))
        return finish_duplicate(entry, near, resumed:)
      end

      import_fetched(batch, connection, entry, provider.fetch(activity), resumed:, provider:, activity:)
    rescue Allure::RemoteImports::Error::NotFound
      skip_entry(entry, "no_file")
    rescue Allure::RemoteImports::Error::NoGeometry
      skip_entry(entry, "no_geometry")
    rescue Allure::RemoteImports::Error
      entry.update!(status: "queued") unless entry.terminal?
      raise
    rescue StandardError => error
      fail_entry(entry, error.message)
    ensure
      batch.refresh_progress! unless batch.terminal?
    end

    def import_fetched(batch, connection, entry, fetched, resumed: false, provider: nil, activity: nil)
      digest = digest_io(fetched.io)
      entry.update_columns(source_digest: digest, metadata: entry.metadata.merge(fetched_metadata(fetched)))

      if (existing = batch.user.workouts.find_by(source_digest: digest))
        return finish_duplicate(entry, existing, resumed:)
      end

      result = Workouts::Importer.new(
        user: batch.user,
        uploaded_file: fetched.io,
        sport: batch.sport || connection.fallback_sport,
        declared_sport: fetched.declared_sport ? Sport.active.find_by(slug: fetched.declared_sport) : nil,
        title: fetched.title,
        description: fetched.description,
        commute: fetched.commute,
        notes: batch.notes,
        filename: fetched.filename,
        source_digest: digest,
        equipment_ids: equipment_ids(connection, fetched),
        import_connection: connection,
        external_id: entry.external_id,
        # A retrieval over a date range is history; the scheduled sync and the
        # webhooks bring new outings (docs/dev/AUTO-PUBLISHING.md).
        bulk: batch.trigger == "manual"
      ).call

      if result.success?
        entry.update_columns(metadata: entry.metadata.merge(
          "imported_title" => result.workout.title, "imported_sport" => result.workout.sport.slug
        ))
        finish_entry(entry, status: "imported", workout: result.workout, sport_source: result.sport_source)
        attach_photos(batch, provider, entry, activity, result.workout)
      elsif result.duplicate?
        finish_duplicate(entry, connection.workouts.find_by(external_id: entry.external_id) ||
                                batch.user.workouts.find_by(source_digest: digest), resumed:)
      elsif result.errors == [ I18n.t("workouts.import.errors.missing_sport") ]
        skip_entry(entry, "unsupported_sport")
      else
        fail_entry(entry, result.errors.join(", "))
      end
    ensure
      close(fetched.io)
    end

    # The photos the provider offers with the activity (docs/dev/REMOTE-IMPORTS.md
    # §7d.3 for Zwift): attached through the same pipeline as the owner's own
    # uploads, so the stripped derivatives, the account quota and the
    # per-workout cap apply. A photo the pipeline refuses is counted, a photo
    # the provider announced but could not download is counted as missing, and
    # nothing here ever fails the import.
    def attach_photos(batch, provider, entry, activity, workout)
      return unless Allure::Photos::Config.enabled? && provider && activity && !workout.photos.exists?

      set = provider.photos(activity)
      counts = Hash.new(0)
      set.photos.each do |photo|
        begin
          PhotoUpload.new(user: batch.user, workout:).call(photo.io)
          counts["photos"] += 1
        rescue PhotoUpload::Invalid
          counts["photos_refused"] += 1
        ensure
          close(photo.io)
        end
      end
      counts["photos_missing"] = set.listed - set.photos.length if set.listed > set.photos.length
      entry.update_columns(metadata: entry.metadata.merge(counts)) if counts.any?
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, entry_id: entry.id })
    end

    # An activity recorded at the same moment already exists, imported some
    # other way (a file, another provider): it is not imported twice. A credit
    # row is not a recording, so the participant's own recording of a credited
    # outing is still imported (docs/dev/SHARED-ACTIVITIES.md).
    def near_duplicate(user, started_at)
      return nil unless started_at

      user.workouts.recordings
        .where(started_at: (started_at - NEAR_DUPLICATE_WINDOW)..(started_at + NEAR_DUPLICATE_WINDOW))
        .min_by { |workout| (workout.started_at - started_at).abs }
    end

    # Gear is attached at import only while the connection synchronises it and
    # the item already exists locally (docs/dev/REMOTE-IMPORTS.md).
    def equipment_ids(connection, fetched)
      return nil unless connection.sync_equipment && fetched.equipment_external_id.present?

      ids = connection.equipments.where(external_id: fetched.equipment_external_id.to_s).pluck(:id)
      ids.presence
    end

    def fetched_metadata(fetched)
      {
        "device_name" => fetched.device_name,
        "equipment_external_id" => fetched.equipment_external_id&.to_s
      }.compact.merge(fetched.metadata.to_h.transform_keys(&:to_s))
    end

    def pause(batch, retry_at)
      retry_at = [ retry_at || 15.minutes.from_now, 1.minute.from_now ].max
      batch.update_columns(paused_until: retry_at, updated_at: Time.current)
      self.class.set(wait_until: retry_at).perform_later(batch)
    end

    def expire(batch)
      connection = batch.import_connection
      ImportConnections::Expiry.new(connection).call if connection
      fail_open_entries(batch, I18n.t("workouts.batch_import.errors.connection_expired"))
      finish_batch(batch)
    end

    # The provider's session reached its natural end (Withings's day, §7c.2):
    # the connection turns `expired` without a notification, and the queued
    # entries stay exactly where they are — the batch page offers to connect
    # again and resume, and the link job re-enqueues what it finds queued.
    def pause_for_reconnect(batch, connection)
      ImportConnections::Expiry.new(connection, notify: false).call if connection
      batch.update_columns(status: "queued", paused_until: nil, updated_at: Time.current)
    end

    def finish_batch(batch)
      batch.reload
      if batch.cancellation_requested?
        batch.entries.where(status: %w[queued processing]).update_all(status: "cancelled", completed_at: Time.current, updated_at: Time.current)
        batch.refresh_progress!
        batch.update!(status: "cancelled", completed_at: Time.current, paused_until: nil)
      else
        fail_open_entries(batch, I18n.t("workouts.batch_import.errors.unfinished_entry"))
        batch.refresh_progress!
        batch.update!(status: "completed", completed_at: Time.current, paused_until: nil)
      end
      enqueue_route_suggestion_sweep(batch)
    end

    # A manual retrieval skipped the per-recording route-suggestion pass; the
    # account sweep now walks its recordings newest first (PLAN_SEGMENTS.md
    # §7.7). A scheduled sync does not, since its imports are not bulk.
    def enqueue_route_suggestion_sweep(batch)
      return unless batch.status == "completed"
      return unless batch.trigger == "manual"
      return if batch.user.deactivated?

      Segments::RouteSuggestionSweepJob.set(priority: BacklogPriority::PRIORITY).perform_later(batch.user_id)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, batch_id: batch.id })
    end

    def fail_batch(batch, error)
      return if batch.reload.terminal?

      fail_open_entries(batch, error.message)
      batch.refresh_progress!
      batch.update_columns(status: "failed", error_message: error.message, completed_at: Time.current,
                           paused_until: nil, updated_at: Time.current)
    end

    def fail_open_entries(batch, message)
      batch.entries.where(status: %w[queued processing]).update_all(
        status: "failed", error_message: message, completed_at: Time.current, updated_at: Time.current
      )
    end

    # The workout this very entry created before an interruption is imported,
    # not a duplicate of itself (Workouts::ImportResumption).
    def finish_duplicate(entry, workout, resumed:)
      status = ImportResumption.claims?(entry:, workout:, resumed:) ? "imported" : "duplicate"
      finish_entry(entry, status:, workout:)
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

    def digest_io(io)
      io.rewind
      digest = Digest::SHA256.new
      while (chunk = io.read(64 * 1024))
        digest.update(chunk)
      end
      io.rewind
      digest.hexdigest
    end

    def close(io)
      return unless io

      io.respond_to?(:close!) ? io.close! : io.close
    rescue IOError
      nil
    end
  end
end
