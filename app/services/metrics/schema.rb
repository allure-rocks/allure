# frozen_string_literal: true

module Metrics
  # Declares every Allure metric. Prometheus names are prefixed by the `allure`
  # group, so `gauge :users` becomes `allure_users`. The name and label
  # vocabulary is the stable interface documented in docs/dev/METRICS.md
  class Schema
    GAUGES = [
      { name: :info, tags: %i[version], comment: "Build identity; always 1." },

      { name: :users, tags: %i[state], comment: "Accounts by state." },
      { name: :users_new_7d, comment: "Registrations in the last 7 days." },
      { name: :users_new_30d, comment: "Registrations in the last 30 days." },
      { name: :users_active_workout_24h, comment: "Distinct accounts with a workout created in 24 hours." },
      { name: :users_active_workout_7d, comment: "Distinct accounts with a workout created in 7 days." },
      { name: :users_active_workout_30d, comment: "Distinct accounts with a workout created in 30 days." },
      { name: :users_active_publication_7d, comment: "Distinct accounts publishing in 7 days." },
      { name: :users_active_publication_30d, comment: "Distinct accounts publishing in 30 days." },
      { name: :users_active_7d, comment: "Distinct accounts active (workout or publication) in 7 days." },
      { name: :users_active_30d, comment: "Distinct accounts active (workout or publication) in 30 days." },
      { name: :sessions_open, comment: "Open sessions (a device holding a valid session)." },
      { name: :users_connected, comment: "Distinct accounts holding at least one open session." },
      { name: :users_second_factor, tags: %i[state], comment: "Accounts by second-factor obligation." },
      { name: :users_sign_in_methods, tags: %i[method], comment: "Accounts holding a password, or a provider identity." },
      { name: :workouts, comment: "Workouts." },
      { name: :workouts_new_7d, comment: "Workouts created in the last 7 days." },
      { name: :workouts_new_30d, comment: "Workouts created in the last 30 days." },
      { name: :workouts_distance_meters, comment: "Summed workout distance." },
      { name: :workouts_moving_seconds, comment: "Summed workout moving time." },
      { name: :workout_publications, tags: %i[status audience], comment: "Workout publications." },
      { name: :segment_publications, tags: %i[status audience], comment: "Course publications." },
      { name: :segments, tags: %i[kind visibility], comment: "Reusable segments." },
      { name: :segment_efforts, comment: "Matched segment efforts." },
      { name: :import_batches, tags: %i[status source], comment: "Import batches by status and source." },
      { name: :import_failed_entries, comment: "Failed import entries." },
      { name: :import_connections, tags: %i[provider status], comment: "Remote import connections." },
      { name: :import_connection_sync_age_seconds, tags: %i[provider],
        comment: "Age of the oldest last sync among linked auto-sync connections of an enabled provider." },
      { name: :import_connection_errors, tags: %i[provider], comment: "Linked connections whose last sync failed." },
      { name: :api_tokens, tags: %i[status], comment: "API tokens by status." },
      { name: :webhook_endpoints, tags: %i[status], comment: "Webhook endpoints by status." },
      { name: :webhook_deliveries, tags: %i[status], comment: "Webhook deliveries created in the last 24 hours, by status." },
      { name: :webhook_delivery_oldest_pending_seconds, comment: "Age of the oldest pending webhook delivery." },
      { name: :push_subscriptions, comment: "Push subscriptions of signed-in companion sessions." },
      { name: :account_exports, tags: %i[status], comment: "Account data exports by status." },
      { name: :funding_contributions, tags: %i[provider tier status], comment: "Voluntary instance contributions by provider, tier and status." },
      { name: :photos, tags: %i[status], comment: "Owner workout photos by processing status." },
      { name: :photo_bytes, comment: "Owner photo bytes, originals and derivatives." },
      { name: :workout_weathers, tags: %i[status], comment: "Workout weather rows by status." },
      { name: :workout_summaries, tags: %i[status], comment: "Assistant summary rows by status." },
      { name: :account_deletions_scheduled, comment: "Accounts in their deletion window or purge." },
      { name: :storage_blobs, comment: "Active Storage blobs." },
      { name: :storage_bytes, comment: "Active Storage bytes." },
      { name: :storage_attachments, tags: %i[record_type], comment: "Attachments by owning record type." },
      { name: :storage_bytes_by_record, tags: %i[record_type name], comment: "Attachment bytes by owner and name." },
      { name: :database_size_bytes, tags: %i[database], comment: "On-disk database size." },

      { name: :jobs_ready, tags: %i[queue], comment: "Solid Queue ready executions." },
      { name: :jobs_scheduled, tags: %i[queue], comment: "Solid Queue scheduled executions." },
      { name: :jobs_claimed, tags: %i[queue], comment: "Solid Queue claimed executions." },
      { name: :jobs_blocked, tags: %i[queue], comment: "Solid Queue blocked executions." },
      { name: :jobs_failed, tags: %i[queue], comment: "Solid Queue failed executions." },
      { name: :jobs_latency_seconds, tags: %i[queue], comment: "Age of the oldest ready execution." },
      { name: :jobs_paused, tags: %i[queue], comment: "1 when the queue is paused." },
      { name: :jobs_processes, tags: %i[kind state], comment: "Worker processes by heartbeat state." },
      { name: :jobs_recurring_last_run_age_seconds, tags: %i[task], comment: "Age of the last recurring enqueue." },
      { name: :jobs_database_up, comment: "1 when the queue database answers." },

      { name: :federation_inbox_items, tags: %i[status], comment: "Inbound activities by status." },
      { name: :federation_deliveries, tags: %i[status], comment: "Outbound deliveries by status." },
      { name: :federation_deliveries_open_oldest_age_seconds, comment: "Age of the oldest open delivery." },
      { name: :federation_outbox_events, tags: %i[status], comment: "Outbox events by status." },
      { name: :federation_outbox_events_by_activity, tags: %i[activity_type], comment: "Outbox events by activity type." },
      { name: :federation_remote_notes, tags: %i[status], comment: "Remote notes by status." },
      { name: :federation_remote_segments, tags: %i[status], comment: "Remote courses by status." },
      { name: :federation_media, tags: %i[status], comment: "Remote media attachments by status." },
      { name: :federation_follows, tags: %i[status], comment: "Follow relationships by status." },
      { name: :federation_remote_actors, tags: %i[capability_profile], comment: "Remote actors by capability." },
      { name: :federation_blocked_domains, comment: "Blocked domains." },
      { name: :federation_blocked_actors, comment: "Blocked actors." },
      { name: :federation_peer_policies, comment: "Promoted peer policies." },
      { name: :federation_retryable_media, comment: "Failed or unavailable remote media." },

      { name: :process_start_time_seconds, comment: "Process start time." },
      { name: :process_resident_memory_bytes, comment: "Resident memory where the platform exposes it." },
      { name: :process_threads, comment: "Live threads." },
      { name: :gc_count, tags: %i[type], comment: "GC runs." },
      { name: :gc_live_slots, comment: "GC live slots." }
    ].freeze

    COUNTERS = [
      { name: :api_requests_total, tags: %i[scope status_class],
        comment: "REST API requests by the scope the operation needs and the status class answered." },
      { name: :mcp_requests_total, tags: %i[method tool outcome],
        comment: "MCP JSON-RPC requests by method, tool and outcome." },
      { name: :federation_inbox_refusals_total, tags: %i[reason],
        comment: "Inbound activities refused before admission: invalid, unknown_recipient, blocked, rate_limited or unavailable." },
      { name: :push_deliveries_total, tags: %i[result],
        comment: "Push deliveries to the relay by result: delivered, gone, rejected or failed." },
      { name: :weather_requests_total, tags: %i[endpoint result],
        comment: "Open-Meteo requests by endpoint (forecast, archive) and result (ok, unavailable, rejected)." },
      { name: :ai_requests_total, tags: %i[kind result],
        comment: "Assistant provider calls by kind and result (ok, invalid, rejected, unavailable)." },
      { name: :ai_tokens_total, tags: %i[kind direction],
        comment: "Tokens reported by the assistant provider, by kind and direction (prompt, completion)." }
    ].freeze

    HISTOGRAMS = [
      { name: :best_efforts_rebuild_duration_seconds, tags: %i[phase context],
        buckets: [ 0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30, 60 ],
        comment: "Best-efforts rebuild duration; phase is compute or persist, context import, reanalysis, backfill, or credit." },
      { name: :ai_request_duration_seconds, tags: %i[kind],
        buckets: [ 1, 2.5, 5, 10, 20, 30, 60, 120, 300 ],
        comment: "Assistant provider call duration, by kind." }
    ].freeze

    class << self
      def define!
        return if Yabeda.metrics.key?("allure_info")

        gauges = GAUGES
        counters = COUNTERS
        histograms = HISTOGRAMS
        Yabeda.configure do
          group :allure
          gauges.each do |declaration|
            gauge declaration[:name], tags: declaration[:tags], comment: declaration[:comment]
          end
          counters.each do |declaration|
            counter declaration[:name], tags: declaration[:tags], comment: declaration[:comment]
          end
          histograms.each do |declaration|
            histogram declaration[:name], tags: declaration[:tags], buckets: declaration[:buckets],
                      comment: declaration[:comment]
          end
        end
      end
    end
  end
end
