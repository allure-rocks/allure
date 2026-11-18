# frozen_string_literal: true

module Metrics
  # Fills the declared gauges from Metrics::Cache and the local process state.
  # Yabeda runs this on every scrape (collect block); each emission family is
  # isolated so a failing query never takes down the exposition
  # (docs/dev/METRICS.md).
  class Collector
    PROCESS_KINDS = %w[Worker Dispatcher Scheduler Supervisor].freeze

    class << self
      def mark_started!(at = Time.current)
        @started_at = at.to_f
      end

      def started_at = @started_at

      def refresh!
        snapshot = Cache.fetch
        safely { emit_info }
        safely { emit_process }
        safely { emit_domain(snapshot.domain) }
        safely { emit_activity(snapshot.activity) }
        safely { emit_users(snapshot.users) }
        safely { emit_storage(snapshot.storage) }
        safely { emit_databases(snapshot.databases) }
        safely { emit_jobs(snapshot.jobs) }
        safely { emit_federation(snapshot.federation) }
      end

      private

      # One scrape-emitting family must not break the others. The snapshot
      # already isolates database failures; this is the emission backstop.
      def safely
        yield
      rescue StandardError => error
        Rails.error.report(error, handled: true, context: { component: name })
      end

      def set(metric, labels, value)
        Yabeda.allure.public_send(metric).set(labels, value)
      end

      def emit_info
        set(:info, { version: Allure::VERSION }, 1)
      end

      def emit_process
        set(:process_start_time_seconds, {}, started_at || Time.current.to_f)
        rss = resident_memory_bytes
        set(:process_resident_memory_bytes, {}, rss) if rss
        set(:process_threads, {}, Thread.list.size)
        set(:gc_count, { type: "major" }, GC.stat(:major_gc_count))
        set(:gc_count, { type: "minor" }, GC.stat(:minor_gc_count))
        set(:gc_live_slots, {}, GC.stat(:heap_live_slots))
      end

      def resident_memory_bytes
        line = File.foreach("/proc/self/status").find { |entry| entry.start_with?("VmRSS:") }
        line&.split&.at(1)&.to_i&.* 1024
      rescue SystemCallError
        nil
      end

      def emit_domain(domain)
        return unless domain

        domain[:users].each { |state, count| set(:users, { state: state.to_s }, count) }
        set(:users_new_7d, {}, domain[:users_new_7d])
        set(:users_new_30d, {}, domain[:users_new_30d])
        set(:workouts, {}, domain[:workouts])
        set(:workouts_new_7d, {}, domain[:workouts_new_7d])
        set(:workouts_new_30d, {}, domain[:workouts_new_30d])
        set(:workouts_distance_meters, {}, domain[:workouts_distance_meters])
        set(:workouts_moving_seconds, {}, domain[:workouts_moving_seconds])
        each_combination(WorkoutPublication::STATUSES, PublishingProfile::AUDIENCES,
                         domain[:workout_publications]) do |status, audience, count|
          set(:workout_publications, { status: status, audience: audience }, count)
        end
        each_combination(SegmentPublication::STATUSES, SegmentPublication::AUDIENCES,
                         domain[:segment_publications]) do |status, audience, count|
          set(:segment_publications, { status: status, audience: audience }, count)
        end
        each_combination(Segment::KINDS, Allure::VisibilityLevel::LEVELS, domain[:segments]) do |kind, visibility, count|
          set(:segments, { kind: kind, visibility: visibility }, count)
        end
        set(:segment_efforts, {}, domain[:segment_efforts])
        each_combination(WorkoutImportBatch::STATUSES, WorkoutImportBatch::SOURCES,
                         domain[:import_batches]) do |status, source, count|
          set(:import_batches, { status: status, source: source }, count)
        end
        set(:import_failed_entries, {}, domain[:import_failed_entries])
        each_combination(ImportConnection::PROVIDERS, ImportConnection::STATUSES,
                         domain[:import_connections]) do |provider, status, count|
          set(:import_connections, { provider: provider, status: status }, count)
        end
        each_label(ImportConnection::PROVIDERS, domain[:import_connection_sync_age]) do |provider, age|
          set(:import_connection_sync_age_seconds, { provider: provider }, age)
        end
        each_label(ImportConnection::PROVIDERS, domain[:import_connection_errors]) do |provider, count|
          set(:import_connection_errors, { provider: provider }, count)
        end
        emit_api(domain)
        emit_funding(domain) if Allure::Funding.enabled?
      end

      def emit_funding(domain)
        %w[manual stripe helloasso other].product(Allure::Funding::TIERS, %w[active upcoming expired revoked]).each do |provider, tier, status|
          count = domain.fetch(:funding_contributions, {}).fetch([ provider, tier, status ], 0)
          set(:funding_contributions, { provider:, tier:, status: }, count)
        end
      end

      API_TOKEN_STATUSES = %w[active expired revoked].freeze
      WEBHOOK_ENDPOINT_STATUSES = %w[active inactive disabled].freeze

      def emit_api(domain)
        each_label(API_TOKEN_STATUSES, domain[:api_tokens]) { |status, count| set(:api_tokens, { status: }, count) }
        each_label(WEBHOOK_ENDPOINT_STATUSES, domain[:webhook_endpoints]) do |status, count|
          set(:webhook_endpoints, { status: }, count)
        end
        each_label(WebhookDelivery::STATUSES, domain[:webhook_deliveries]) do |status, count|
          set(:webhook_deliveries, { status: }, count)
        end
        set(:webhook_delivery_oldest_pending_seconds, {}, domain[:webhook_delivery_oldest_pending].to_i)
        set(:push_subscriptions, {}, domain[:push_subscriptions].to_i)
        each_label(WorkoutPhoto::STATUSES, domain[:photos]) { |status, count| set(:photos, { status: }, count) }
        set(:photo_bytes, {}, domain[:photo_bytes].to_i)
        each_label(WorkoutWeather::STATUSES, domain[:workout_weathers]) do |status, count|
          set(:workout_weathers, { status: }, count)
        end
        each_label(WorkoutSummary::STATUSES, domain[:workout_summaries]) do |status, count|
          set(:workout_summaries, { status: }, count)
        end
        each_label(AccountExport::STATUSES, domain[:account_exports]) do |status, count|
          set(:account_exports, { status: }, count)
        end
        set(:account_deletions_scheduled, {}, domain[:account_deletions_scheduled].to_i)
      end

      def emit_activity(activity)
        return unless activity

        set(:users_active_workout_24h, {}, activity["workout_24h"])
        set(:users_active_workout_7d, {}, activity["workout_7d"])
        set(:users_active_workout_30d, {}, activity["workout_30d"])
        set(:users_active_publication_7d, {}, activity["publication_7d"])
        set(:users_active_publication_30d, {}, activity["publication_30d"])
        set(:users_active_7d, {}, activity["active_7d"])
        set(:users_active_30d, {}, activity["active_30d"])
      end

      def emit_users(users)
        return unless users

        set(:sessions_open, {}, users[:sessions_open])
        set(:users_connected, {}, users[:users_connected])
        users[:second_factor]&.each { |state, count| set(:users_second_factor, { state: }, count) }
        users[:sign_in_methods]&.each { |method, count| set(:users_sign_in_methods, { method: }, count) }
      end

      def emit_storage(storage)
        return unless storage

        set(:storage_blobs, {}, storage[:blobs])
        set(:storage_bytes, {}, storage[:bytes])
        storage[:attachments].each do |record_type, count|
          set(:storage_attachments, { record_type: record_type.underscore }, count)
        end
        storage[:bytes_by_record].each do |(record_type, name), bytes|
          set(:storage_bytes_by_record, { record_type: record_type.underscore, name: name }, bytes)
        end
      end

      def emit_databases(databases)
        return unless databases

        databases.each { |name, bytes| set(:database_size_bytes, { database: name }, bytes) }
      end

      def emit_jobs(jobs)
        if jobs.nil?
          set(:jobs_database_up, {}, 0)
          return
        end

        set(:jobs_database_up, {}, 1)
        emit_queues(jobs[:queues])
        PROCESS_KINDS.each do |kind|
          set(:jobs_processes, { kind: kind, state: "alive" }, jobs[:processes][:alive].fetch(kind, 0))
          set(:jobs_processes, { kind: kind, state: "stale" }, jobs[:processes][:stale].fetch(kind, 0))
        end
        jobs[:recurring].each do |task, last_run|
          set(:jobs_recurring_last_run_age_seconds, { task: task }, (Time.current - last_run).to_i)
        end
      end

      def emit_queues(queues)
        (QueueName::KNOWN + [ QueueName::OTHER ]).each do |name|
          row = queues[name] || {}
          %i[ready scheduled claimed blocked failed].each do |state|
            set(:"jobs_#{state}", { queue: name }, row.fetch(state, 0))
          end
          set(:jobs_latency_seconds, { queue: name }, row.fetch(:latency, 0))
          set(:jobs_paused, { queue: name }, row.fetch(:paused, false) ? 1 : 0)
        end
      end

      def emit_federation(federation)
        return unless federation

        each_label(FederationInboxItem::STATUSES, federation[:inbox_items]) do |status, count|
          set(:federation_inbox_items, { status: status }, count)
        end
        each_label(FederationDelivery::STATUSES, federation[:deliveries]) do |status, count|
          set(:federation_deliveries, { status: status }, count)
        end
        oldest = federation[:deliveries_oldest_open]
        set(:federation_deliveries_open_oldest_age_seconds, {}, oldest ? (Time.current - oldest).to_i : 0)
        each_label(FederationOutboxEvent::STATUSES, federation[:outbox_events]) do |status, count|
          set(:federation_outbox_events, { status: status }, count)
        end
        each_label(FederationOutboxEvent::ACTIVITY_TYPES, federation[:outbox_by_activity]) do |type, count|
          set(:federation_outbox_events_by_activity, { activity_type: type }, count)
        end
        each_label(RemoteNote::STATUSES, federation[:remote_notes]) do |status, count|
          set(:federation_remote_notes, { status: status }, count)
        end
        each_label(RemoteSegment::STATUSES, federation[:remote_segments]) do |status, count|
          set(:federation_remote_segments, { status: status }, count)
        end
        each_label(RemoteNoteAttachment::STATUSES, federation[:media]) do |status, count|
          set(:federation_media, { status: status }, count)
        end
        each_label(Following::STATUSES, federation[:follows]) do |status, count|
          set(:federation_follows, { status: status }, count)
        end
        each_label(Actor::CAPABILITY_PROFILES, federation[:remote_actors]) do |profile, count|
          set(:federation_remote_actors, { capability_profile: profile }, count)
        end
        set(:federation_blocked_domains, {}, federation[:blocked_domains])
        set(:federation_blocked_actors, {}, federation[:blocked_actors])
        set(:federation_peer_policies, {}, federation[:peer_policies])
        set(:federation_retryable_media, {}, federation[:retryable_media])
      end

      def each_label(labels, counts)
        labels.each { |label| yield label, counts.fetch(label, 0) }
      end

      def each_combination(firsts, seconds, counts)
        firsts.each do |first|
          seconds.each { |second| yield first, second, counts.fetch([ first, second ], 0) }
        end
      end
    end
  end
end
