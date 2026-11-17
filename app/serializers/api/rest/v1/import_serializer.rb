# frozen_string_literal: true

module Api
  module Rest
    module V1
      # An import batch and, in the detail form, its entries (docs/dev/API.md,
      # §7.5): the counters and states the web's import progress shows.
      class ImportSerializer
        def initialize(batch, entries: nil)
          @batch = batch
          @entries = entries
        end

        def as_json(*)
          batch = @batch
          body = {
            id: batch.to_param,
            status: batch.status,
            source: batch.source,
            trigger: batch.trigger,
            fallback_sport: batch.sport&.slug,
            notes: batch.notes,
            cancellation_requested: batch.cancellation_requested?,
            counts: {
              total: batch.total_entries,
              processed: batch.processed_entries,
              imported: batch.imported_entries,
              duplicate: batch.duplicate_entries,
              skipped: batch.skipped_entries,
              failed: batch.failed_entries,
              cancelled: batch.cancelled_entries
            },
            error: batch.error_message,
            created_at: Formats.time(batch.created_at),
            started_at: Formats.time(batch.started_at),
            completed_at: Formats.time(batch.completed_at),
            links: { self: "#{Allure::Federation.config.base_url}/api/rest/v1/imports/#{batch.to_param}" }
          }
          body[:entries] = @entries.map { entry(it) } if @entries
          body
        end

        private

        def entry(entry)
          {
            position: entry.position,
            name: entry.source_name,
            path: entry.source_path,
            status: entry.status,
            skip_reason: entry.skip_reason,
            sport_source: entry.sport_source,
            error: entry.error_message,
            workout_id: entry.workout&.to_param,
            started_at: Formats.time(entry.started_at),
            completed_at: Formats.time(entry.completed_at)
          }
        end
      end
    end
  end
end
