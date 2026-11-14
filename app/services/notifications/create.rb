# frozen_string_literal: true

module Notifications
  # The single write seam for in-app notifications (PLAN_NOTIFICATIONS.md).
  # Producers pass the recipient, the kind, the actor, and the relationship it
  # describes; this service enforces the recipient's preferences, idempotency
  # through the unique index, and the per-account cap. It never fails its
  # caller: a notification is a side effect of a relationship change, not part
  # of it, so an unexpected error is reported and swallowed.
  class Create
    PREFERENCES = {
      "follow_request" => :notify_follow_requests,
      "follow_accepted" => :notify_follow_accepted,
      "publication_activated" => :notify_publication_activated,
      "reaction" => :notify_reactions,
      "participation_requested" => :notify_participation_requests,
      "participation_suggested" => :notify_participation_requests,
      "participation_confirmed" => :notify_participation_confirmed,
      "participation_source_deleted" => :notify_participation_confirmed,
      "participation_link_suggested" => :notify_participation_confirmed,
      "comment" => :notify_comments,
      "import_connection_expired" => :notify_import_connections,
      "import_connection_revoked" => :notify_import_connections,
      "auto_published" => :notify_auto_published,
      "auto_publication_failed" => :notify_auto_publication_failed,
      "webhook_disabled" => :notify_webhooks,
      # The account asked for its export: telling it is part of the answer,
      # so no switch turns it off (PLAN_ACCOUNT.md §3.2).
      "account_export_ready" => nil,
      "funding_recorded" => nil
    }.freeze

    # `alert: false` is for a reaction whose account only switched its type:
    # the digest recounts without turning unread again (§8).
    def initialize(user:, kind:, actor: nil, subject: nil, payload: {}, alert: true)
      @user = user
      @kind = kind.to_s
      @actor = actor
      @subject = subject
      @payload = payload
      @alert = alert
    end

    def call!
      return if @user.nil?
      return if @user.deactivated?
      return if @actor && @actor.user_id == @user.id

      emit_webhook
      preference = PREFERENCES.fetch(@kind)
      return if preference && !@user.public_send(preference)

      notification = @kind == ReactionDigest::KIND ? record_reaction : record_notification
      return unless notification

      prune!
      # A repeated producer call finds its row and pushes nothing; the
      # reaction digest decides itself whether it alerted (§8).
      PushJob.enqueue_after_commit(notification) if notification.previously_new_record? && @kind != ReactionDigest::KIND
      notification
    rescue ActiveRecord::RecordNotUnique
      nil
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, kind: @kind })
      nil
    end

    private

    # The webhook event of the same fact goes whatever the in-app switch
    # says: subscribing an endpoint is the preference (PLAN_API.md §11.2). It
    # is a side effect of the side effect: a failure there is reported and
    # never costs the in-app notification.
    def emit_webhook
      Webhooks::Events.from_notification(user: @user, kind: @kind, actor: @actor, subject: @subject, payload: @payload)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, kind: @kind, step: "webhook" })
    end

    # A repeated producer call (a re-sent follow request, a redelivered
    # activity) finds its row first: inserting into the unique index would be
    # refused and logged as an error by PostgreSQL. The insert only settles a
    # race between two first calls.
    def record_notification
      attributes = { user: @user, kind: @kind, subject: @subject }
      Notification.find_by(attributes) || Notification.create_or_find_by!(attributes) do |record|
        record.actor = @actor
        record.payload = @payload
      end
    end

    # Reactions on one workout share one digest (§8); the webhook above still
    # carries each reaction.
    def record_reaction
      workout = @subject.try(:workout)
      return unless workout && workout.user_id == @user.id

      ReactionDigest.new(workout:).record!(alert: @alert)
    end

    # The inbox is bounded: the oldest rows beyond the cap are dropped as new
    # ones arrive, except an unread one still awaiting a decision, so a burst
    # of reactions or comments never erases a pending request.
    def prune!
      overflow = Notification.where(user: @user)
        .recent_first
        .offset(Notification::MAX_PER_USER)
        .select(:id)
      prunable = Notification.where(id: overflow)
      prunable
        .where.not(read_at: nil)
        .or(prunable.where.not(kind: Notification::ACTIONABLE_KINDS))
        .delete_all
    end
  end
end
