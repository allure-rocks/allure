# frozen_string_literal: true

module Admin
  module Dashboard
    # Aggregates the instance's headline numbers for the administration
    # dashboard: account, activity, publication, federation, storage, queue,
    # and import counts plus the most recent rows. It is counts and identifiers
    # only — never coordinates, payloads, keys, or remote HTML (PLAN_ADMIN.md).
    #
    # Everything is a bounded count or a top-5 list: the page must stay cheap on
    # an instance with years of activities.
    class Overview
      Result = Data.define(
        :accounts, :workouts, :publications, :federation, :storage, :queue, :imports,
        :recent_accounts, :recent_publications, :recent_events, :recent_imports
      )

      def call
        Result.new(
          accounts: accounts,
          workouts: workouts,
          publications: publications,
          federation: federation,
          storage: storage,
          queue: queue,
          imports: imports,
          recent_accounts: User.order(created_at: :desc, id: :desc).limit(5),
          recent_publications: WorkoutPublication.active
            .order(published_at: :desc, id: :desc)
            .includes(workout: :user)
            .limit(5),
          recent_events: AdminEvent.recent_first.includes(:user).limit(5),
          recent_imports: WorkoutImportBatch.order(created_at: :desc, id: :desc).includes(:user).limit(5)
        )
      end

      private

      def accounts
        engagement = Users::Engagement.new
        {
          total: User.count,
          week: User.where(created_at: window(7)).count,
          month: User.where(created_at: window(30)).count,
          active_week: engagement.active(since: 7.days.ago),
          connected: engagement.connected
        }
      end

      # Recordings only: a credit row repeats an outing already counted
      # (docs/dev/SHARED-ACTIVITIES.md).
      def workouts
        recordings = Workout.recordings
        {
          total: recordings.count,
          week: recordings.where(created_at: window(7)).count,
          month: recordings.where(created_at: window(30)).count,
          distance: recordings.sum(:distance),
          moving_time: recordings.sum(:moving_time)
        }
      end

      def publications
        {
          active: WorkoutPublication.active.count,
          public: WorkoutPublication.publicly_visible.count,
          followers: WorkoutPublication.followers_visible.count,
          scheduled: WorkoutPublication.scheduled.count,
          courses: SegmentPublication.active.count
        }
      end

      def federation
        {
          remote_actors: Actor.remote.count,
          followed: Following.accepted.count,
          pending_follows: Following.where(status: "pending").count,
          remote_notes: RemoteNote.active.count,
          remote_segments: RemoteSegment.active.count,
          outbox_open: FederationOutboxEvent.where(status: %w[preparing pending expanded]).count,
          deliveries_open: FederationDelivery.where(status: %w[pending retrying delivering reconciling]).count
        }
      end

      def storage
        {
          blobs: ActiveStorage::Blob.count,
          bytes: ActiveStorage::Blob.sum(:byte_size),
          attachments: ActiveStorage::Attachment.group(:record_type).count
        }
      end

      # The queue database is a separate connection. When it is unreachable the
      # dashboard must still render, with the queue card saying so.
      def queue
        {
          ready: SolidQueue::ReadyExecution.count,
          scheduled: SolidQueue::ScheduledExecution.count,
          failed: SolidQueue::FailedExecution.count
        }
      rescue StandardError => error
        Rails.error.report(error, handled: true, context: { component: self.class.name })
        nil
      end

      def imports
        {
          failed_entries: WorkoutImportEntry.where(status: "failed").count,
          connections_linked: ImportConnection.linked.count,
          connections_relink: ImportConnection.where(status: ImportConnection::RELINK_STATUSES).count
        }
      end

      def window(days)
        days.days.ago..Time.current
      end
    end
  end
end
