# frozen_string_literal: true

# Presentation rules for shared activities (docs/dev/SHARED-ACTIVITIES.md, DESIGN.md §10.18).
# The card names accounts through the shared actor helpers and states the kind
# and the state as badges; it never renders a location, a distance, or a score.
module ParticipationsHelper
  def participation_kind_label(participation)
    t("workouts.participations.kinds.#{participation.kind}")
  end

  # Rows are live-scoped, so a withdrawn row never reaches the card; the
  # state is pending, suggested (a detection awaiting either side),
  # confirmed, or declined.
  def participation_state_label(participation)
    state = if participation.declined?
      "declined"
    elsif participation.confirmed?
      "confirmed"
    elsif participation.origin == "detection"
      "suggested"
    else
      "pending"
    end
    t("workouts.participations.states.#{state}")
  end

  # The viewer's open suggestions to link this recording to a credit
  # (docs/dev/SHARED-ACTIVITIES.md), for the banner on the recording's own page.
  def open_link_suggestions_for(recording)
    actor = current_user&.actor
    return [] unless actor && recording.recording? && recording.user_id == current_user.id

    WorkoutParticipation.confirmed.credits
      .where(suggested_workout: recording, participant_actor: actor, link_suggestion_dismissed_at: nil)
      .includes(:workout, :suggested_workout).to_a
  end

  # A detection still waiting for the given side's answer (docs/dev/SHARED-ACTIVITIES.md).
  def participation_awaits_side?(participation, side)
    return false unless participation.origin == "detection" && participation.active?

    side == :owner ? participation.owner_confirmed_at.nil? : participation.participant_confirmed_at.nil?
  end

  # The live links naming this workout as the participant's recording, for its
  # own card: confirmed links and detections to answer.
  def participation_links_on(workout)
    workout.participant_links.live.includes(workout: { user: :actor }).order(:created_at, :id).to_a
  end

  # A tombstoned participant renders as a deleted account, without a handle
  # (docs/dev/SHARED-ACTIVITIES.md); the avatar falls back to generated art.
  def participation_actor_name(actor)
    return t("workouts.participations.deleted_account") if actor_deleted?(actor)

    actor_name(actor)
  end

  def participation_actor_handle(actor)
    return nil if actor_deleted?(actor)

    actor_handle(actor)
  end

  # The « Avec @X » badge names the source owner on a participant's page.
  def participation_badge_text(workout)
    t("workouts.participations.badge", name: workout.user.display_name)
  end

  # A credit row names the account that recorded it; once its source is
  # deleted, the badge says so (docs/dev/SHARED-ACTIVITIES.md).
  def credit_badge_text(workout)
    name = participation_actor_name(workout.credited_by)
    workout.credit_detached? ? t("workouts.credit.badge_detached", name:) : t("workouts.participations.badge", name:)
  end

  # The source's publication as the viewer may read it, for a credit row's
  # route image and map (docs/dev/SHARED-ACTIVITIES.md): never the source's own media.
  # A remote credit reads its received note instead (§7). Nil once detached
  # or when nothing serves the viewer.
  def credit_source_display(workout)
    @credit_source_displays ||= {}
    return @credit_source_displays[workout.id] if @credit_source_displays.key?(workout.id)

    @credit_source_displays[workout.id] = workout.credit_remote? ? remote_credit_view(workout) : local_credit_view(workout)
  end

  # The route image of what `credit_source_display` returned, in a theme.
  def credit_source_image_path(workout, view, theme: nil)
    if view.is_a?(Workouts::PublicationView)
      publication_route_image_path(view.publication, theme:)
    else
      remote_note_route_image_path(workout.remote_participation.remote_note, theme:)
    end
  end

  def local_credit_view(workout)
    source = workout.credited_from
    publication = Workouts::PublicationResolver.new(workout: source, user: current_user).call if source
    Workouts::PublicationView.new(publication, principal: Workouts::PublicationPrincipal.browser(current_user)) if publication
  end

  def remote_credit_view(workout)
    note = workout.remote_participation&.remote_note
    return unless note&.active? && !workout.credit_detached?

    policy = Federation::RemoteNotePolicy.new(note:, principal: Workouts::PublicationPrincipal.browser(current_user))
    Federation::RemoteNoteView.new(note) if policy.allowed?(resource: :note)
  end

  # The viewer's recordings of the same outing the link picker offers
  # (docs/dev/SHARED-ACTIVITIES.md): their own, starting within six hours of the
  # source, closest first.
  def participation_recording_candidates(participation)
    return [] unless current_user && participation

    Participations::RecordingRules.candidates(participation:, user: current_user).to_a
  end

  def participation_recording_options(workouts)
    workouts.map do |workout|
      [ "#{workout_display_title(workout)} · #{format_started_at(workout.started_at)}", workout.to_param ]
    end
  end

  # The confirmed links naming this workout as the participant's recording: a
  # lien shows on both workouts (DESIGN.md §10.18).
  def participation_links_for(workout)
    workout.participant_links.confirmed.includes(workout: :user).order(:created_at, :id)
  end

  # The owner's « Avec @X » badge (DESIGN.md §10.18), on the workout header
  # and, icon-only, on its card: a credit row names the account that recorded
  # it — grey once its source is deleted — a source names its confirmed
  # participants, and the owner's own recording the sources it is linked to.
  # Every name joins one badge; it links to the source only when it names a
  # single linked source, never to a profile. Lists that preloaded
  # `workout_participations` and `participant_links` are read without another
  # query. Participants are live state for the owner only: they never enter a
  # publication (docs/dev/SHARED-ACTIVITIES.md).
  def owner_together_badges(workout, fit: :auto)
    if workout.credit?
      source = workout.credited_from
      return together_badge(credit_badge_text(workout), href: (workout_path(source) if source),
                                                        detached: workout.credit_detached?, fit:)
    end

    participants = confirmed_rows(workout, :workout_participations) { workout.workout_participations.confirmed.includes(participant_actor: :user) }
    links = confirmed_rows(workout, :participant_links) { participation_links_for(workout) }
    names = (participants.map { |row| participation_actor_name(row.participant_actor) } +
             links.map { |link| link.workout.user.display_name }).uniq
    return "".html_safe if names.empty?

    href = workout_path(links.first.workout) if participants.empty? && links.one?
    together_badge(together_badge_text(names), tooltip: together_badge_text(names, full: true), href:, fit:)
  end

  # « Avec Eva », « Avec Eva et Joan », then « Avec Eva et 2 autres »; `full`
  # names everyone, for the tooltip.
  def together_badge_text(names, full: false)
    name = if full || names.size <= 2
      names.to_sentence(words_connector: t("workouts.participations.names.words_connector"),
                        two_words_connector: t("workouts.participations.names.last_word_connector"),
                        last_word_connector: t("workouts.participations.names.last_word_connector"))
    else
      t("workouts.participations.names.others", name: names.first, count: names.size - 1)
    end
    t("workouts.participations.badge", name:)
  end

  # Confirmed rows of a participation association, ordered, from the preload
  # when the list made one.
  def confirmed_rows(workout, association)
    rows = workout.association(association).loaded? ? workout.public_send(association).select(&:confirmed?) : yield.to_a
    rows.sort_by { |row| [ row.created_at, row.id ] }
  end

  # The owner sees every live row, including refusals; a participant only sees
  # confirmed rows, so a pending invitation to someone else stays private.
  def participation_visible_rows(workout, owner)
    rows = workout.workout_participations.live.includes(participant_actor: :user).order(:created_at, :id)
    owner ? rows : rows.select(&:confirmed?)
  end
end
