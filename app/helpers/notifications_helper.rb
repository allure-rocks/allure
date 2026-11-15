# frozen_string_literal: true

# Presentation rules for the in-app inbox (PLAN_NOTIFICATIONS.md). Every string
# is localized and every remote account is rendered through the shared actor
# helpers, so no copy names the protocol (DESIGN.md §24).
module NotificationsHelper
  def unread_notifications_count
    @unread_notifications_count ||= current_user ? current_user.notifications.unread.count : 0
  end

  def notification_bell_label(count)
    count.positive? ? t("notifications.bell.label_unread", count:) : t("notifications.bell.label")
  end

  def notification_text(notification)
    actor = notification.actor
    case notification.kind
    when "follow_request"
      actor_deleted?(actor) ? t("notifications.kinds.follow_request_deleted") : t("notifications.kinds.follow_request", name: actor_name(actor))
    when "follow_accepted"
      actor_deleted?(actor) ? t("notifications.kinds.follow_accepted_deleted") : t("notifications.kinds.follow_accepted", name: actor_name(actor))
    when "import_connection_expired", "import_connection_revoked"
      provider = notification.payload.to_h["provider"].to_s
      label = I18n.exists?("workouts.batch_import.sources.#{provider}.label") ? t("workouts.batch_import.sources.#{provider}.label") : provider
      key = notification.kind
      key = "import_connection_revoked_operator" if key == "import_connection_revoked" && notification.payload.to_h["by"] == "operator"
      t("notifications.kinds.#{key}", provider: label)
    when "publication_activated"
      title = publication_notification_title(notification)
      title.present? ? t("notifications.kinds.publication_activated", title:) : t("notifications.kinds.publication_activated_untitled")
    when "reaction"
      reaction_notification_text(notification)
    when "participation_requested", "participation_suggested", "participation_confirmed"
      participation_notification_text(notification)
    when "participation_link_suggested"
      participation = notification.subject
      if participation.is_a?(WorkoutParticipation) && participation.workout
        t("notifications.kinds.participation_link_suggested", title: workout_display_title(participation.workout))
      else
        t("notifications.kinds.participation_link_suggested_unavailable")
      end
    when "participation_source_deleted"
      credit = notification.subject
      if credit.is_a?(Workout)
        t("notifications.kinds.participation_source_deleted", title: workout_display_title(credit))
      else
        t("notifications.kinds.participation_source_deleted_unavailable")
      end
    when "comment"
      comment_notification_text(notification)
    when "auto_published"
      auto_published_notification_text(notification)
    when "webhook_disabled"
      reason = notification.payload.to_h["reason"].to_s
      t("notifications.kinds.webhook_disabled.#{%w[gone failing operator].include?(reason) ? reason : 'failing'}",
        host: notification.payload.to_h["host"].to_s)
    when "account_export_ready"
      t("notifications.kinds.account_export_ready")
    when "funding_recorded"
      t("funding.recorded")
    when "auto_publication_failed"
      title = notification.subject.is_a?(WorkoutAutoPublication) ? notification.subject.workout&.title.presence : nil
      title ? t("notifications.kinds.auto_publication_failed", title:) : t("notifications.kinds.auto_publication_failed_untitled")
    end
  end

  # The destination a notification opens: the decisions hub for an incoming
  # request, the account itself once accepted, the workout for an activation
  # notice. A missing actor or source always falls back to the inbox rather
  # than a dead link.
  def notification_target_path(notification)
    case notification.kind
    when "follow_request"
      people_path
    when "follow_accepted"
      actor_deleted?(notification.actor) ? notifications_path : actor_profile_path(notification.actor)
    when "publication_activated"
      publication = notification.subject
      publication.is_a?(WorkoutPublication) && publication.workout ? workout_path(publication.workout) : notifications_path
    when "reaction"
      reaction_notification_path(notification)
    when "participation_requested", "participation_suggested", "participation_confirmed"
      participation_notification_path(notification)
    when "participation_source_deleted"
      notification.subject.is_a?(Workout) ? workout_path(notification.subject) : notifications_path
    when "participation_link_suggested"
      recording = notification.subject.try(:suggested_workout)
      recording ? workout_path(recording) : notifications_path
    when "comment"
      comment_notification_path(notification)
    when "auto_published"
      publication = notification.subject
      publication.is_a?(WorkoutPublication) && publication.workout ? workout_path(publication.workout, anchor: "section-sharing") : notifications_path
    when "auto_publication_failed"
      row = notification.subject
      row.is_a?(WorkoutAutoPublication) && row.workout ? workout_path(row.workout, anchor: "section-sharing") : notifications_path
    when "import_connection_expired", "import_connection_revoked"
      connection = notification.subject
      connection.is_a?(ImportConnection) ? connection_path(connection.provider) : connections_path
    when "account_export_ready"
      settings_account_path(anchor: "account-export")
    when "funding_recorded"
      Allure::Funding.enabled? && !hotwire_native_app? ? settings_profile_path : notifications_path
    when "webhook_disabled"
      endpoint = notification.subject
      endpoint.is_a?(WebhookEndpoint) ? settings_webhook_path(endpoint) : settings_api_path
    else
      notifications_path
    end
  end

  private

  # One digest per workout (PLAN_NOTIFICATIONS.md §8). A single reaction names
  # its gesture (PLAN_REACTIONS.md §5); several name the newest account and
  # count the others.
  def reaction_notification_text(notification)
    workout = notification.subject
    actor = notification.actor
    return t("notifications.kinds.reaction_deleted") if actor_deleted?(actor)
    return t("notifications.kinds.reaction_unavailable", name: actor_name(actor)) unless workout.is_a?(Workout)

    payload = notification.payload.to_h
    count = payload["count"].to_i
    title = workout.title.presence
    if count > 1
      key = title ? "reaction_many" : "reaction_many_untitled"
      return t("notifications.kinds.#{key}", name: actor_name(actor), title:, count: count - 1)
    end

    kind = payload["kinds"].to_h.keys.first.presence_in(Reaction::KINDS) || Reaction::DEFAULT_KIND
    key = title ? "reaction_#{kind}" : "reaction_#{kind}_untitled"
    t("notifications.kinds.#{key}", name: actor_name(actor), title:)
  end

  def reaction_notification_path(notification)
    workout = notification.subject
    workout.is_a?(Workout) ? workout_path(workout) : notifications_path
  end

  # A comment notice names the account and, for the workout's owner, the
  # workout; a reply to the recipient's own comment says so instead, and never
  # names a title the recipient may not be allowed to read (PLAN_COMMENTS.md
  # §10).
  def comment_notification_text(notification)
    comment = notification.subject
    actor = notification.actor
    return t("notifications.kinds.comment_deleted") unless comment.is_a?(Comment) && actor

    name = actor_name(actor)
    return t("notifications.kinds.comment_reply", name:) if comment.parent && comment.parent.actor&.user_id == notification.user_id

    title = comment.workout&.title.presence
    title ? t("notifications.kinds.comment", name:, title:) : t("notifications.kinds.comment_untitled", name:)
  end

  def comment_notification_path(notification)
    comment = notification.subject
    return notifications_path unless comment.is_a?(Comment) && comment.target

    comment_thread_path(comment.target, comment:)
  end

  # A participation notice names the account and the workout. A deleted account
  # reads as such; a participation that no longer exists still names a living
  # account, so the copy never contradicts the avatar beside it.
  def participation_notification_text(notification)
    participation = notification.subject
    actor = notification.actor
    return t("notifications.kinds.#{notification.kind}_deleted") if actor_deleted?(actor)
    # An invitation received from another instance names its received note
    # (PLAN_TOGETHER.md §7).
    if participation.is_a?(RemoteParticipation) && participation.remote_note
      return t("notifications.kinds.#{notification.kind}", name: actor_name(actor), title: participation.remote_note.title)
    end
    unless participation.is_a?(WorkoutParticipation)
      return t("notifications.kinds.#{notification.kind}_unavailable", name: actor_name(actor))
    end

    t("notifications.kinds.#{notification.kind}",
      name: actor_name(actor),
      title: workout_display_title(participation.workout))
  end

  # The participant of a link opens their own recording, where a detection is
  # answered and the source stays closed until both confirmed; everyone else
  # opens the source.
  def participation_notification_path(notification)
    participation = notification.subject
    return remote_note_path(participation.remote_note) if participation.is_a?(RemoteParticipation) && participation.remote_note
    return notifications_path unless participation.is_a?(WorkoutParticipation) && participation.workout

    recording = participation.participant_workout
    return workout_path(recording) if recording && participation.participant_actor.user_id == notification.user_id

    workout_path(participation.workout)
  end

  # The automatic-publication notice says whether the workout is already live
  # or held by the profile's delay, and until when (docs/dev/AUTO-PUBLISHING.md).
  def auto_published_notification_text(notification)
    title = publication_notification_title(notification).presence
    scheduled_for = Time.zone.parse(notification.payload.to_h["scheduled_for"].to_s) if notification.payload.to_h["scheduled_for"].present?
    if scheduled_for
      date = l(scheduled_for.in_time_zone(Time.find_zone(notification.user.time_zone) || Time.zone), format: :long)
      title ? t("notifications.kinds.auto_scheduled", title:, date:) : t("notifications.kinds.auto_scheduled_untitled", date:)
    else
      title ? t("notifications.kinds.auto_published", title:) : t("notifications.kinds.auto_published_untitled")
    end
  end

  # The activation notice describes the frozen snapshot, not the source, so a
  # later source edit never rewrites an old notification.
  def publication_notification_title(notification)
    publication = notification.subject
    return "" unless publication.is_a?(WorkoutPublication)

    publication.publication_title.to_s
  end
end
