# frozen_string_literal: true

# Presentation rules for the comments card (PLAN_COMMENTS.md §11, DESIGN.md
# §10.20). One card serves the thread this instance hosts on a workout and the
# thread another instance hosts for a received note; it reads who the viewer
# is, what the policy lets them do, and why a thread is closed, and it never
# names the protocol.
module CommentsHelper
  # Everything the card renders for one target and the current viewer.
  # `publication` is the one a new comment hangs on — the narrowest serving
  # the viewer — and `publications` every active one the owner may write
  # under, or the one serving a reader (docs/dev/PUBLISHING.md); `audiences`
  # the threads the viewer reads.
  CommentCard = Data.define(:target, :listing, :permission, :owner, :publication, :publications, :audiences) do
    def entries = listing.entries
    def active_count = listing.active_count
    def postable? = permission == :allowed
    def closed? = permission == :closed
    def received? = target.is_a?(RemoteNote)

    def closed_by_profile?
      return target.representation["comments_closed"] == true if received?

      publication&.comments_closed_by_profile? == true
    end

    def closed_live? = !received? && target.comments_closed_at.present?

    # The owner keeps reading a thread after its publication went away; any
    # other reader needs the publication or the note the thread hangs on.
    def visible?
      owner ? publication.present? || entries.any? : permission != :denied
    end

    def switchable? = owner && publications.any? { |candidate| !candidate.comments_closed_by_profile? }

    # The owner picks the thread of a new comment when several audiences are
    # published.
    def audience_choice? = owner && publications.count(&:comments_open?) > 1

    # Audience badges only help when the viewer reads more than one thread.
    def several_audiences? = !received? && audiences.many?
  end

  def comment_card_for(target)
    workout = target.is_a?(Workout)
    owner = workout && current_user.present? && target.user_id == current_user.id
    audiences = workout ? Workouts::ReadableAudiences.for(user: current_user, workout: target) : []
    publication = (Comments::Post.publication_for(user: current_user, workout: target) if workout && current_user)
    publications = if owner
      WorkoutPublication.by_precedence(target.active_publications.to_a)
    else
      Array(publication)
    end
    CommentCard.new(
      target:,
      listing: Comments::Listing.new(target:, viewer: current_user&.actor, audiences: (audiences if workout)).call,
      permission: comment_permission(target, owner ? publications : []),
      owner:,
      publication:,
      publications:,
      audiences:
    )
  end

  # The owner may write while any of their publications takes comments; any
  # other reader through the one serving them.
  def comment_permission(target, owned_publications)
    return Comments::Post.permission(user: current_user, target:) if owned_publications.empty?
    return :allowed if owned_publications.any?(&:comments_open?)

    :closed
  end

  # The page's targets are counted once; a target the controller did not
  # announce is counted on its own instead of silently reading as zero.
  def comment_count_for(target)
    @comment_counts ||= Comments::Counts.new(targets: @comment_targets.presence || [ target ], viewer: current_user).call
    @comment_counts.fetch(target) do
      @comment_counts[target] = Comments::Counts.new(targets: [ target ], viewer: current_user).call.fetch(target, 0)
    end
  end

  def comments_frame_id(target) = "comments-#{target.model_name.element.dasherize}-#{target.to_param}"

  def comment_dom_id(comment) = "comment-#{comment.to_param}"

  def comment_reply_dom_id(comment) = "comment-reply-#{comment.to_param}"

  def comment_create_path(target)
    target.is_a?(RemoteNote) ? remote_note_comments_path(target) : workout_comments_path(target)
  end

  # The thread's own page: every screen reaches it the same way, the phone
  # layout having no card on the workout page (DESIGN.md §10.20).
  def comment_thread_path(target, comment: nil)
    anchor = comment ? comment_dom_id(comment) : nil
    target.is_a?(RemoteNote) ? remote_note_comments_path(target, anchor:) : workout_comments_path(target, anchor:)
  end

  # A local author is named by their account, like the feed; a remote one by
  # the cached actor with its instance handle (DESIGN.md §24); a deleted
  # account by the generic words. A deactivated local account (suspended, or
  # inside its deletion window) is not named either: its comment stays, its
  # identity does not show (PLAN_COMMENTS.md §7.6).
  def comment_author_name(actor)
    return t("comments.author.deleted") if actor.nil? || actor.tombstoned?
    return t("comments.author.unavailable") if comment_author_deactivated?(actor)
    return actor.user.display_name if actor.local? && actor.user

    actor_name(actor)
  end

  def comment_author_handle(actor)
    return if actor.nil? || actor.tombstoned? || comment_author_deactivated?(actor)
    return "@#{actor.user.username}" if actor.local? && actor.user

    actor_handle(actor)
  end

  def comment_author_path(actor)
    return if actor.nil? || actor.tombstoned? || comment_author_deactivated?(actor)

    actor_profile_path(actor)
  end

  # The author's avatar, or a neutral generated one for an account that is
  # not named.
  def comment_author_avatar_tag(actor)
    return actor_avatar_tag(actor, size: "sm") unless comment_author_deactivated?(actor)

    render "shared/generated_avatar", seed: Zlib.crc32(actor.uri.to_s), classes: "avatar avatar-sm", label: nil
  end

  def comment_author_deactivated?(actor)
    actor.present? && actor.local? && actor.user.present? && actor.user.deactivated?
  end

  # A local author's text is plain and escaped, line breaks kept; a remote
  # author's is the sanitized subset, sanitized again on the way out.
  def comment_body(comment)
    return simple_format(h(comment.body), {}, wrapper_tag: "p") if comment.content_html.blank?

    Federation::RemoteText.sanitize(comment.content_html).to_s.html_safe
  end

  # The viewer's own comment that left the thread, named by why.
  def comment_state_label(comment)
    if comment.rejected?
      comment.removal_reason == "closed" ? t("comments.states.rejected_closed") : t("comments.states.rejected")
    elsif comment.removed?
      t("comments.states.removed")
    end
  end

  def comment_stub_text(comment)
    if comment.deleted?
      t("comments.stub.deleted")
    elsif comment.removal_reason == Comments::Remove::REASON
      t("comments.stub.removed_by_owner")
    else
      t("comments.stub.removed")
    end
  end

  # `audience` is the thread the composer writes to: a reply's comment, else
  # the card's publication.
  def comment_privacy_text(card, audience: nil)
    if card.received?
      # The origin relays a comment on its public publication to the other
      # instances that received it (PLAN_COMMENTS.md §6.6), never a followers one.
      key = card.target.public? ? "comments.privacy.received_public" : "comments.privacy.received"
      t(key, handle: actor_handle(card.target.actor))
    elsif card.audience_choice? && audience.nil?
      t("comments.privacy.choice")
    elsif (audience || card.publication&.audience) == "followers"
      t("comments.privacy.followers")
    else
      t("comments.privacy.public")
    end
  end

  # The owner's thread picker: one option per published audience, the
  # narrowest first.
  def comment_audience_options(card)
    card.publications.select(&:comments_open?)
      .map { |publication| [ t("comments.audience.#{publication.audience}"), publication.audience ] }
  end

  def comment_closed_text(card)
    return t("comments.closed") unless card.owner && card.closed_by_profile?

    t("comments.closed_by_profile", profile: card.publication.profile_snapshot["name"].to_s)
  end
end
