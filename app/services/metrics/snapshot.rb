# frozen_string_literal: true

module Metrics
  # Builds every database-derived metric value in one pass for the Prometheus
  # exporter (PLAN_METRICS.md §4). Each family is rescued independently: a
  # failing family is omitted from the exposition, never propagated into
  # Yabeda's collect block.
  #
  # Everything here is a bounded count or sum over check-constrained enums and
  # fixed queue names. No query returns user-supplied identifiers, domains, or
  # payloads.
  class Snapshot
    Result = Data.define(:domain, :activity, :users, :storage, :databases, :jobs, :federation)

    def call
      Result.new(
        domain: safe { domain_family },
        activity: safe { activity_family },
        users: safe { users_family },
        storage: safe { storage_family },
        databases: safe { databases_family },
        jobs: safe { jobs_family },
        federation: safe { federation_family }
      )
    end

    private

    def safe
      yield
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name })
      nil
    end

    def domain_family
      {
        users: {
          active: User.where(suspended_at: nil).count,
          suspended: User.where.not(suspended_at: nil).count
        },
        users_new_7d: User.where(created_at: 7.days.ago..).count,
        users_new_30d: User.where(created_at: 30.days.ago..).count,
        # Recordings only: a credit row repeats an outing already counted
        # (PLAN_TOGETHER.md §6.6).
        workouts: Workout.recordings.count,
        workouts_new_7d: Workout.recordings.where(created_at: 7.days.ago..).count,
        workouts_new_30d: Workout.recordings.where(created_at: 30.days.ago..).count,
        workouts_distance_meters: Workout.recordings.sum(:distance).to_f,
        workouts_moving_seconds: Workout.recordings.sum(:moving_time).to_i,
        workout_publications: WorkoutPublication
          .group(:status, :audience).count,
        segment_publications: SegmentPublication.group(:status, :audience).count,
        segments: Segment.group(:kind, :visibility).count,
        segment_efforts: SegmentEffort.count,
        import_batches: WorkoutImportBatch.group(:status, :source).count,
        import_failed_entries: WorkoutImportEntry.where(status: "failed").count,
        import_connections: ImportConnection.group(:provider, :status).count,
        import_connection_sync_age: import_connection_sync_age,
        import_connection_errors: ImportConnection.linked.where.not(last_sync_error: [ nil, "" ]).group(:provider).count,
        api_tokens: api_token_counts,
        webhook_endpoints: webhook_endpoint_counts,
        webhook_deliveries: WebhookDelivery.where(created_at: 24.hours.ago..).group(:status).count,
        webhook_delivery_oldest_pending: oldest_pending_delivery_age,
        push_subscriptions: PushSubscription.count,
        account_exports: AccountExport.group(:status).count,
        funding_contributions: funding_contribution_counts,
        photos: WorkoutPhoto.group(:status).count,
        photo_bytes: WorkoutPhoto.sum(:bytes_total),
        workout_weathers: WorkoutWeather.group(:status).count,
        account_deletions_scheduled: User.where.not(deletion_scheduled_at: nil).count
      }
    end

    # No arbitrary provider slug becomes a label: an operator's custom adapter
    # is counted as `other`, keeping the label vocabulary bounded.
    def funding_contribution_counts
      return {} unless Allure::Funding.enabled?

      provider = Arel.sql("CASE WHEN provider IN ('manual', 'stripe', 'helloasso') THEN provider ELSE 'other' END")
      # Use the same application clock as badge eligibility. PostgreSQL's
      # CURRENT_TIMESTAMP is fixed at transaction start, not at scrape time.
      now = FundingContribution.connection.quote(Time.current)
      status = Arel.sql("CASE WHEN status = 'revoked' THEN 'revoked' WHEN expires_at <= #{now} THEN 'expired' WHEN starts_at > #{now} THEN 'upcoming' ELSE 'active' END")
      FundingContribution.group(provider, :tier, status).count
    end

    # PLAN_API.md §14: never a host, an account or a token.
    def api_token_counts(now = Time.current)
      {
        "revoked" => ApiToken.where.not(revoked_at: nil).count,
        "expired" => ApiToken.unrevoked.where(expires_at: ..now).count,
        "active" => ApiToken.usable(now).count
      }
    end

    def webhook_endpoint_counts
      {
        "disabled" => WebhookEndpoint.where.not(disabled_at: nil).count,
        "inactive" => WebhookEndpoint.where(disabled_at: nil, active: false).count,
        "active" => WebhookEndpoint.deliverable.count
      }
    end

    def oldest_pending_delivery_age(now = Time.current)
      oldest = WebhookDelivery.pending.minimum(:created_at)
      oldest ? (now - oldest).to_i.clamp(0..) : 0
    end

    # Seconds since the stalest sync of each enabled provider's linked
    # auto-sync connections (a connection never synced counts from its link),
    # so a stuck hourly sync shows as a growing age.
    def import_connection_sync_age(now = Time.current)
      ImportConnection.linked.where(auto_sync: true, provider: Allure::RemoteImports::Config.enabled_providers)
        .group(:provider).minimum(Arel.sql("COALESCE(last_synced_at, linked_at)"))
        .transform_values { |oldest| oldest ? (now - oldest).to_i.clamp(0..) : 0 }
    end

    # Active users are activity-based: a sign-in alone does not count
    # (PLAN_METRICS.md §3). The definition is shared with the administration
    # dashboard through Users::Engagement.
    def activity_family
      engagement = Users::Engagement.new
      {
        "workout_24h" => engagement.active_workout(since: 24.hours.ago),
        "workout_7d" => engagement.active_workout(since: 7.days.ago),
        "workout_30d" => engagement.active_workout(since: 30.days.ago),
        "publication_7d" => engagement.active_publication(since: 7.days.ago),
        "publication_30d" => engagement.active_publication(since: 30.days.ago),
        "active_7d" => engagement.active(since: 7.days.ago),
        "active_30d" => engagement.active(since: 30.days.ago)
      }
    end

    # "Connected" is session-based: a session row exists only while a device
    # holds a valid session (sign-out and revocation delete it).
    def users_family
      engagement = Users::Engagement.new
      { sessions_open: engagement.open_sessions, users_connected: engagement.connected,
        second_factor: Auth::SecondFactorPolicy.counts,
        sign_in_methods: { "password" => User.where.not(password_digest: nil).count,
                           "provider" => Identity.distinct.count(:user_id) } }
    end

    def storage_family
      {
        blobs: ActiveStorage::Blob.count,
        bytes: ActiveStorage::Blob.sum(:byte_size).to_i,
        attachments: ActiveStorage::Attachment.group(:record_type).count,
        bytes_by_record: ActiveStorage::Attachment.joins(:blob)
          .group(:record_type, :name).sum("active_storage_blobs.byte_size")
      }
    end

    def databases_family
      {
        "primary" => database_size(ActiveRecord::Base.connection),
        "queue" => database_size(SolidQueue::Record.connection),
        "cable" => database_size(SolidCable::Record.connection)
      }.compact
    end

    def database_size(connection)
      connection.select_value("SELECT pg_database_size(current_database())").to_i
    rescue StandardError
      nil
    end

    def jobs_family
      threshold = SolidQueue.process_alive_threshold.ago
      {
        queues: queue_family,
        processes: {
          alive: SolidQueue::Process.where(last_heartbeat_at: threshold..).group(:kind).count,
          stale: SolidQueue::Process.where(last_heartbeat_at: ...threshold).group(:kind).count
        },
        recurring: SolidQueue::RecurringTask.order(:key).filter_map do |task|
          [ task.key, task.last_enqueued_time ] if task.last_enqueued_time
        end.to_h
      }
    end

    def queue_family
      ready = SolidQueue::ReadyExecution.group(:queue_name).count
      scheduled = SolidQueue::ScheduledExecution.group(:queue_name).count
      claimed = SolidQueue::ClaimedExecution.joins(:job).group("solid_queue_jobs.queue_name").count
      blocked = SolidQueue::BlockedExecution.group(:queue_name).count
      failed = SolidQueue::FailedExecution.joins(:job).group("solid_queue_jobs.queue_name").count
      oldest = SolidQueue::ReadyExecution.group(:queue_name).minimum(:created_at)
      paused = SolidQueue::Pause.pluck(:queue_name)
      now = Time.current

      names = (ready.keys | scheduled.keys | claimed.keys | blocked.keys | failed.keys | paused).map do |name|
        Metrics::QueueName.normalize(name)
      end.uniq.sort

      names.index_with do |name|
        {
          ready: sum_for_queue(ready, name),
          scheduled: sum_for_queue(scheduled, name),
          claimed: sum_for_queue(claimed, name),
          blocked: sum_for_queue(blocked, name),
          failed: sum_for_queue(failed, name),
          latency: oldest_for_queue(oldest, name, now),
          paused: paused.any? { |queue| Metrics::QueueName.normalize(queue) == name }
        }
      end
    end

    def sum_for_queue(counts, name)
      counts.sum { |queue, count| Metrics::QueueName.normalize(queue) == name ? count : 0 }
    end

    def oldest_for_queue(oldest, name, now)
      times = oldest.filter_map do |queue, time|
        time if Metrics::QueueName.normalize(queue) == name
      end
      times.empty? ? 0 : (now - times.min).to_i
    end

    def federation_family
      {
        inbox_items: status_counts(FederationInboxItem),
        deliveries: status_counts(FederationDelivery),
        deliveries_oldest_open: FederationDelivery
          .where(status: %w[pending retrying delivering reconciling]).minimum(:created_at),
        outbox_events: status_counts(FederationOutboxEvent),
        outbox_by_activity: FederationOutboxEvent.group(:activity_type).count,
        remote_notes: status_counts(RemoteNote),
        remote_segments: status_counts(RemoteSegment),
        media: media_counts,
        follows: status_counts(Following),
        remote_actors: Actor.remote.group(:capability_profile).count,
        blocked_domains: FederationDomainBlock.count,
        blocked_actors: FederationActorBlock.count,
        peer_policies: FederationPeerPolicy.count,
        retryable_media: retryable_media_count
      }
    end

    def status_counts(model) = model.group(:status).count

    def media_counts
      combined = Hash.new(0)
      [ RemoteNoteAttachment, RemoteSegmentAttachment ].each do |model|
        model.group(:status).count.each { |status, count| combined[status] += count }
      end
      combined
    end

    def retryable_media_count
      [ RemoteNoteAttachment, RemoteSegmentAttachment ].sum do |model|
        model.where(status: %w[failed unavailable]).count
      end
    end
  end
end
