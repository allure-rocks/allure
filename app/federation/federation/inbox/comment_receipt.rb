# frozen_string_literal: true

module Federation
  module Inbox
    # Receives one comment carried by a Create with `inReplyTo`
    # (docs/dev/COMMENTS.md). The `inReplyTo` names the thread: a local
    # publication or a comment on it makes this instance the host, which
    # authorizes the author through the publication's policy and answers a
    # refusal with a Reject; a received note or a comment on it means the
    # origin's own comment reaches its reader. Idempotent by comment identity,
    # and a withdrawn comment never comes back.
    class CommentReceipt
      # Where the comment lands: a local workout this instance hosts (with the
      # publication that gates it and its host actor), or a received note.
      Discussion = Data.define(:workout, :remote_note, :parent, :publication, :host, :warnings) do
        def hosted_here? = remote_note.nil?
        def audience = hosted_here? ? publication.audience : remote_note.audience
      end

      def initialize(item:, activity:, outbox_events:, now: Time.current)
        @item = item
        @activity = activity
        @outbox_events = outbox_events
        @now = now
      end

      def call!
        raise Rejected, "activity actor does not match the sender" unless @activity["actor"] == @item.actor_uri

        author = remote_actor!
        @value = Parsers::RemoteComment.new(@activity).call
        existing = ::Comment.find_by(uri: @value.object_uri)
        return known_comment(existing, author) if existing

        discussion = resolve_discussion!(author)
        authorize!(discussion, author)
        create!(discussion, author)
      rescue Parsers::RemoteComment::InvalidObject => error
        raise Rejected, error.message
      rescue ActiveRecord::RecordInvalid => error
        raise Rejected, "invalid remote comment: #{error.record.errors.full_messages.to_sentence}"
      end

      private

      def remote_actor!
        actor = Actor.find_by(uri: @item.actor_uri)
        raise Rejected, "author is not available" unless actor&.remote? && !actor.tombstoned?
        raise Rejected, "author is blocked" if Safety::Blocks.blocked?(actor.uri)

        actor
      end

      # A redelivery, or the copy delivered to another local recipient, finds
      # the row again; a withdrawn comment stays withdrawn.
      def known_comment(comment, author)
        raise Rejected, "comment author does not match" unless comment.actor_id == author.id
        raise Rejected, "comment was already withdrawn" unless comment.active?

        comment
      end

      def resolve_discussion!(author)
        uri = @value.in_reply_to
        publication = WorkoutPublication.find_by(object_uri: uri)
        return hosted(publication.workout, publication:, host: publication.actor, parent: nil) if publication

        parent = ::Comment.find_by(uri:)
        return discussion_of(parent, author) if parent

        note = RemoteNote.find_by(object_uri: uri)
        return received(note, author, parent: nil) if note

        # The host answers a comment this instance never received: the reply
        # waits on the thread its `context` names until that comment arrives
        # (Comments::Relink).
        note = @value.context && RemoteNote.find_by(object_uri: @value.context)
        return received(note, author, parent: nil, warnings: [ "parent comment not yet received" ]) if note

        raise Rejected, "comment answers an unknown thread"
      end

      # One level of replies: an answer to a reply is attached to its root.
      def discussion_of(parent, author)
        warnings = []
        if parent.parent
          parent = parent.parent
          warnings << "reply depth flattened"
        end
        raise Rejected, "parent comment is not in its thread" unless parent.active?
        return received(parent.remote_note, author, parent:, warnings:) if parent.remote_note

        workout = parent.workout
        # A reply joins its comment's thread: the publication of that audience
        # (docs/dev/PUBLISHING.md).
        hosted(workout, publication: workout.active_publication_for(parent.audience), host: workout.user&.actor, parent:, warnings:)
      end

      def hosted(workout, publication:, host:, parent:, warnings: [])
        Discussion.new(workout:, remote_note: nil, parent:, publication:, host:, warnings:)
      end

      # Another instance hosts this thread: only its host writes to this
      # instance about it, and only to an account that holds the note.
      def received(note, author, parent:, warnings: [])
        raise Rejected, "the received note is no longer active" unless note&.active?
        raise Rejected, "only the thread host comments here" unless note.actor_id == author.id
        unless note.public? || note.entitled_to?(@item.recipient_actor)
          raise Rejected, "the recipient does not hold the received note"
        end
        raise Rejected, "the received thread is full" if ::Comment.for_target(note).active.count >= ::Comment::MAX_ACTIVE_PER_THREAD

        Discussion.new(workout: nil, remote_note: note, parent:, publication: nil, host: note.actor, warnings:)
      end

      # This instance hosts the thread: the publication's policy decides, and
      # a refusal travels back to the author (docs/dev/COMMENTS.md).
      def authorize!(discussion, author)
        return unless discussion.hosted_here?

        publication = discussion.publication
        live = discussion.workout && publication&.active? && publication.workout_id == discussion.workout.id
        refuse!(discussion, author, "inactive") unless live

        policy = Workouts::PublicationPolicy.new(publication:, principal: Workouts::PublicationPrincipal.protocol(author))
        refuse!(discussion, author, "not_allowed") unless policy.allowed?(resource: :workout)
        refuse!(discussion, author, "closed") unless policy.allowed?(resource: :comment)
        return if ::Comment.for_target(discussion.workout).active.count < ::Comment::MAX_ACTIVE_PER_THREAD

        refuse!(discussion, author, "full")
      end

      def refuse!(discussion, author, reason)
        if discussion.host
          @outbox_events << Outbox::CommentReject.new(
            host_actor: discussion.host,
            author_uri: author.uri,
            create_activity_uri: @item.activity_uri,
            comment_uri: @value.object_uri,
            reason:
          ).call!
        end
        raise Rejected, "comment refused: #{reason}"
      end

      def create!(discussion, author)
        comment = ::Comment.transaction(requires_new: true) do
          ::Comment.create!(
            actor: author,
            workout: discussion.workout,
            remote_note: discussion.remote_note,
            parent: discussion.parent,
            in_reply_to_uri: @value.in_reply_to,
            uri: @value.object_uri,
            activity_uri: @item.activity_uri,
            audience: discussion.audience,
            body: @value.body,
            content_html: @value.content_html,
            published_at: @value.published_at || @now,
            source_domain: Allure::Federation::Authority.domain(author.uri),
            raw: @value.raw,
            warnings: (@value.warnings + discussion.warnings).first(Parsers::RemoteComment::MAX_WARNINGS)
          )
        end
        Comments::Relink.call!(comment)
        Comments::Notifier.notify!(comment)
        relay!(discussion, comment)
        comment
      rescue ActiveRecord::RecordNotUnique
        # A concurrent delivery for another local recipient stored it first.
        known_comment(::Comment.find_by!(uri: @value.object_uri), author)
      end

      # The host relays what it accepted to every instance its public
      # publication went to (docs/dev/COMMENTS.md), the author's included,
      # which learns the comment was taken.
      def relay!(discussion, comment)
        return unless discussion.hosted_here? && discussion.publication.audience == "public"

        @outbox_events << Outbox::CommentAnnounce.new(comment:, publication: discussion.publication).call!
      end
    end
  end
end
