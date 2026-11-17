# frozen_string_literal: true

module Metrics
  # The contract between the exporter and the administration console
  # (docs/dev/METRICS.md). Every exported family declares the console concept it
  # mirrors: `admin` is an i18n key the operator can see, or nil for technical
  # families (HTTP/process internals) with no admin counterpart.
  #
  # The guard spec keeps this list, Metrics::Schema, and the i18n corpus in
  # sync, so a new gauge cannot land without deciding what it corresponds to.
  module Catalog
    Entry = Data.define(:family, :kind, :admin)

    GAUGES = [
      Entry.new(family: "allure_info", kind: :gauge, admin: "admin.system.versions"),

      Entry.new(family: "allure_users", kind: :gauge, admin: "admin.dashboard.accounts.title"),
      Entry.new(family: "allure_users_new_7d", kind: :gauge, admin: "admin.dashboard.trend"),
      Entry.new(family: "allure_users_new_30d", kind: :gauge, admin: "admin.dashboard.trend"),
      Entry.new(family: "allure_users_active_workout_24h", kind: :gauge,
                admin: "admin.dashboard.accounts.activity"),
      Entry.new(family: "allure_users_active_workout_7d", kind: :gauge,
                admin: "admin.dashboard.accounts.activity"),
      Entry.new(family: "allure_users_active_workout_30d", kind: :gauge,
                admin: "admin.dashboard.accounts.activity"),
      Entry.new(family: "allure_users_active_publication_7d", kind: :gauge,
                admin: "admin.dashboard.accounts.activity"),
      Entry.new(family: "allure_users_active_publication_30d", kind: :gauge,
                admin: "admin.dashboard.accounts.activity"),
      Entry.new(family: "allure_users_active_7d", kind: :gauge, admin: "admin.dashboard.accounts.activity"),
      Entry.new(family: "allure_users_active_30d", kind: :gauge, admin: "admin.dashboard.accounts.activity"),
      Entry.new(family: "allure_sessions_open", kind: :gauge, admin: "admin.accounts.sessions"),
      Entry.new(family: "allure_users_connected", kind: :gauge, admin: "admin.dashboard.accounts.activity"),
      Entry.new(family: "allure_users_second_factor", kind: :gauge, admin: "admin.accounts.second_factor"),
      Entry.new(family: "allure_users_sign_in_methods", kind: :gauge, admin: "admin.accounts.sign_in_methods"),
      Entry.new(family: "allure_workouts", kind: :gauge, admin: "admin.dashboard.workouts.title"),
      Entry.new(family: "allure_workouts_new_7d", kind: :gauge, admin: "admin.dashboard.trend"),
      Entry.new(family: "allure_workouts_new_30d", kind: :gauge, admin: "admin.dashboard.trend"),
      Entry.new(family: "allure_workouts_distance_meters", kind: :gauge,
                admin: "admin.dashboard.workouts.totals"),
      Entry.new(family: "allure_workouts_moving_seconds", kind: :gauge,
                admin: "admin.dashboard.workouts.totals"),
      Entry.new(family: "allure_workout_publications", kind: :gauge,
                admin: "admin.dashboard.publications.title"),
      Entry.new(family: "allure_segment_publications", kind: :gauge,
                admin: "admin.publications.tabs.courses"),
      Entry.new(family: "allure_segments", kind: :gauge, admin: "admin.publications.tabs.courses"),
      Entry.new(family: "allure_segment_efforts", kind: :gauge, admin: "admin.publications.tabs.courses"),
      Entry.new(family: "allure_import_batches", kind: :gauge, admin: "admin.imports.title"),
      Entry.new(family: "allure_import_failed_entries", kind: :gauge, admin: "admin.dashboard.imports.failed"),
      Entry.new(family: "allure_import_connections", kind: :gauge, admin: "admin.imports.connections.title"),
      Entry.new(family: "allure_import_connection_sync_age_seconds", kind: :gauge,
                admin: "admin.imports.connections.table.last_synced_at"),
      Entry.new(family: "allure_import_connection_errors", kind: :gauge,
                admin: "admin.imports.connections.table.last_error"),
      Entry.new(family: "allure_api_tokens", kind: :gauge, admin: "admin.accounts.api.tokens"),
      Entry.new(family: "allure_webhook_endpoints", kind: :gauge, admin: "admin.accounts.api.webhooks"),
      Entry.new(family: "allure_webhook_deliveries", kind: :gauge, admin: "settings.webhooks.show.deliveries"),
      Entry.new(family: "allure_webhook_delivery_oldest_pending_seconds", kind: :gauge,
                admin: "settings.webhooks.delivery_statuses.pending"),
      Entry.new(family: "allure_push_subscriptions", kind: :gauge, admin: "settings.notifications.push.title"),
      Entry.new(family: "allure_account_exports", kind: :gauge, admin: "admin.accounts.export.title"),
      Entry.new(family: "allure_funding_contributions", kind: :gauge, admin: "funding.admin.title"),
      Entry.new(family: "allure_photos", kind: :gauge, admin: "photos.admin.title"),
      Entry.new(family: "allure_photo_bytes", kind: :gauge, admin: "photos.admin.title"),
      Entry.new(family: "allure_workout_weathers", kind: :gauge, admin: "admin.jobs.weather.title"),
      Entry.new(family: "allure_account_deletions_scheduled", kind: :gauge, admin: "admin.accounts.states.deletion_scheduled"),
      Entry.new(family: "allure_storage_blobs", kind: :gauge, admin: "admin.dashboard.storage.blobs"),
      Entry.new(family: "allure_storage_bytes", kind: :gauge, admin: "admin.dashboard.storage.title"),
      Entry.new(family: "allure_storage_attachments", kind: :gauge,
                admin: "admin.dashboard.storage.title"),
      Entry.new(family: "allure_storage_bytes_by_record", kind: :gauge,
                admin: "admin.dashboard.storage.title"),
      Entry.new(family: "allure_database_size_bytes", kind: :gauge, admin: "admin.system.databases"),

      Entry.new(family: "allure_jobs_ready", kind: :gauge, admin: "admin.jobs.queues.ready"),
      Entry.new(family: "allure_jobs_scheduled", kind: :gauge, admin: "admin.jobs.queues.scheduled"),
      Entry.new(family: "allure_jobs_claimed", kind: :gauge, admin: "admin.jobs.queues.claimed"),
      Entry.new(family: "allure_jobs_blocked", kind: :gauge, admin: "admin.jobs.queues.blocked"),
      Entry.new(family: "allure_jobs_failed", kind: :gauge, admin: "admin.jobs.queues.failed"),
      Entry.new(family: "allure_jobs_latency_seconds", kind: :gauge, admin: "admin.jobs.queues.latency"),
      Entry.new(family: "allure_jobs_paused", kind: :gauge, admin: "admin.jobs.queues.paused"),
      Entry.new(family: "allure_jobs_processes", kind: :gauge, admin: "admin.jobs.processes.title"),
      Entry.new(family: "allure_jobs_recurring_last_run_age_seconds", kind: :gauge,
                admin: "admin.jobs.recurring.title"),
      Entry.new(family: "allure_jobs_database_up", kind: :gauge, admin: "admin.jobs.title"),

      Entry.new(family: "allure_federation_inbox_items", kind: :gauge,
                admin: "settings.federation.activity.inbox"),
      Entry.new(family: "allure_federation_deliveries", kind: :gauge,
                admin: "settings.federation.deliveries.title"),
      Entry.new(family: "allure_federation_deliveries_open_oldest_age_seconds", kind: :gauge,
                admin: "admin.federation.health.oldest"),
      Entry.new(family: "allure_federation_outbox_events", kind: :gauge,
                admin: "admin.dashboard.federation.outbox"),
      Entry.new(family: "allure_federation_outbox_events_by_activity", kind: :gauge, admin: nil),
      Entry.new(family: "allure_federation_remote_notes", kind: :gauge,
                admin: "settings.federation.activity.notes"),
      Entry.new(family: "allure_federation_remote_segments", kind: :gauge,
                admin: "settings.federation.activity.segments"),
      Entry.new(family: "allure_federation_media", kind: :gauge,
                admin: "settings.federation.activity.media"),
      Entry.new(family: "allure_federation_follows", kind: :gauge,
                admin: "admin.dashboard.federation.follows"),
      Entry.new(family: "allure_federation_remote_actors", kind: :gauge,
                admin: "admin.dashboard.federation.title"),
      Entry.new(family: "allure_federation_blocked_domains", kind: :gauge,
                admin: "settings.federation.blocks.domains"),
      Entry.new(family: "allure_federation_blocked_actors", kind: :gauge,
                admin: "settings.federation.blocks.actors"),
      Entry.new(family: "allure_federation_peer_policies", kind: :gauge,
                admin: "settings.federation.policies.title"),
      Entry.new(family: "allure_federation_retryable_media", kind: :gauge,
                admin: "settings.federation.media.title"),

      Entry.new(family: "allure_process_start_time_seconds", kind: :gauge, admin: nil),
      Entry.new(family: "allure_process_resident_memory_bytes", kind: :gauge, admin: nil),
      Entry.new(family: "allure_process_threads", kind: :gauge, admin: nil),
      Entry.new(family: "allure_gc_count", kind: :gauge, admin: nil),
      Entry.new(family: "allure_gc_live_slots", kind: :gauge, admin: nil)
    ].freeze

    # Provided by yabeda-rails, not by Metrics::Schema.
    RAILS = [
      Entry.new(family: "rails_requests_total", kind: :counter, admin: nil),
      Entry.new(family: "rails_request_duration_seconds", kind: :histogram, admin: nil),
      Entry.new(family: "rails_view_runtime_seconds", kind: :histogram, admin: nil),
      Entry.new(family: "rails_db_runtime_seconds", kind: :histogram, admin: nil)
    ].freeze

    # Declared by Metrics::Schema; request counts with no console panel.
    COUNTERS = [
      Entry.new(family: "allure_api_requests_total", kind: :counter, admin: nil),
      Entry.new(family: "allure_mcp_requests_total", kind: :counter, admin: nil),
      Entry.new(family: "allure_federation_inbox_refusals_total", kind: :counter, admin: nil),
      Entry.new(family: "allure_push_deliveries_total", kind: :counter, admin: nil),
      Entry.new(family: "allure_weather_requests_total", kind: :counter, admin: nil)
    ].freeze

    # Declared by Metrics::Schema; technical timings with no console panel.
    HISTOGRAMS = [
      Entry.new(family: "allure_best_efforts_rebuild_duration_seconds", kind: :histogram, admin: nil)
    ].freeze

    # A family that may legitimately be absent from a scrape: RSS is only
    # readable where /proc exists (Linux), not on a developer macOS host.
    OPTIONAL = %w[allure_process_resident_memory_bytes allure_funding_contributions].freeze

    module_function

    def entries = GAUGES + COUNTERS + HISTOGRAMS + RAILS

    def counters = COUNTERS

    def gauges = GAUGES

    def histograms = HISTOGRAMS

    def optional?(family) = OPTIONAL.include?(family)
  end
end
