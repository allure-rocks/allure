# frozen_string_literal: true

module Federation
  module Inbox
    # Receives a thread host's Announce of a comment on its public
    # publication (docs/dev/COMMENTS.md). Only the host relays its own thread,
    # and only a public one. This instance's own comment coming back is
    # confirmed without a fetch; anyone else's is verified against the
    # author's own copy before it is stored, because the host could otherwise
    # put any words in any actor's name. Idempotent by comment identity; a
    # withdrawn comment never comes back.
    class CommentRelay
      def initialize(item:, activity:, now: Time.current, client: nil)
        @item = item
        @activity = activity
        @now = now
        @client = client
      end

      def call!
        raise Rejected, "activity actor does not match the sender" unless @activity["actor"] == @item.actor_uri

        host = remote_actor!
        object = @activity["object"]
        raise Rejected, "the announced comment must be embedded" unless object.is_a?(Hash)

        @value = parse(object)
        existing = ::Comment.find_by(uri: @value.object_uri)
        return known_comment(existing, host) if existing

        note, parent, warnings = resolve_thread!(host)
        author = resolve_author!
        verify!
        create!(note:, parent:, author:, host:, warnings:)
      rescue Parsers::RemoteComment::InvalidObject => error
        raise Rejected, error.message
      rescue CommentFetcher::Refused => error
        raise Rejected, "the author's instance does not confirm the comment: #{error.message}"
      rescue ActorResolver::InvalidActor => error
        raise Rejected, "the comment's author is not valid: #{error.message}"
      rescue ActiveRecord::RecordInvalid => error
        raise Rejected, "invalid relayed comment: #{error.record.errors.full_messages.to_sentence}"
      end

      private

      def remote_actor!
        actor = Actor.find_by(uri: @item.actor_uri)
        raise Rejected, "the thread host is not available" unless actor&.remote? && !actor.tombstoned?
        raise Rejected, "the thread host is blocked" if Safety::Blocks.blocked?(actor.uri)

        actor
      end

      # The relay keeps the author's object as written: the strict comment
      # profile applies with the author, not the announcing host, as its actor.
      def parse(object)
        Parsers::RemoteComment.new({ "actor" => object["attributedTo"], "object" => object }).call
      end

      def known_comment(comment, host)
        raise Rejected, "the relayed comment belongs to another thread" unless thread_host_of(comment) == host
        return comment unless comment.active?

        comment.confirm!(activity_uri: @item.activity_uri, at: @now) if comment.local_author?
        comment
      end

      def thread_host_of(comment) = comment.remote_note&.actor

      def resolve_thread!(host)
        uri = @value.in_reply_to
        parent = ::Comment.find_by(uri:)
        warnings = []
        note = if parent
          if parent.parent
            parent = parent.parent
            warnings << "reply depth flattened"
          end
          parent.remote_note
        else
          RemoteNote.find_by(object_uri: uri) || context_note(warnings)
        end

        validate_thread!(note, host)
        raise Rejected, "parent comment is not in its thread" if parent && !parent.active?

        [ note, parent, warnings ]
      end

      # A reply whose parent this instance never saw waits on the thread its
      # `context` names until the parent arrives (Comments::Relink).
      def context_note(warnings)
        note = @value.context && RemoteNote.find_by(object_uri: @value.context)
        warnings << "parent comment not yet received" if note
        note
      end

      def validate_thread!(note, host)
        raise Rejected, "the relayed comment answers an unknown thread" unless note
        raise Rejected, "only the thread host relays its thread" unless note.actor_id == host.id
        raise Rejected, "the received note is no longer active" unless note.active?
        raise Rejected, "only a public thread is relayed" unless note.public?
        raise Rejected, "the received thread is full" if ::Comment.for_target(note).active.count >= ::Comment::MAX_ACTIVE_PER_THREAD
      end

      def resolve_author!
        uri = @value.attributed_to
        raise Rejected, "the comment's author is blocked" if Safety::Blocks.blocked?(uri)
        raise Rejected, "a local author's comment is unknown here" if Allure::Federation.config.local_uri?(uri)

        author = ActorResolver.new(client:, now: @now).resolve(uri)
        raise Rejected, "the comment's author is not available" unless author.remote? && !author.tombstoned?

        author
      end

      def verify!
        fetched = parse(CommentFetcher.new(signer: @item.recipient_actor, client:).call(@value.object_uri))
        same = %i[object_uri attributed_to in_reply_to body].all? { |field| fetched.public_send(field) == @value.public_send(field) }
        raise Rejected, "the relayed comment does not match its author's copy" unless same
      end

      def create!(note:, parent:, author:, host:, warnings:)
        comment = ::Comment.transaction(requires_new: true) do
          ::Comment.create!(
            actor: author,
            remote_note: note,
            parent:,
            in_reply_to_uri: @value.in_reply_to,
            uri: @value.object_uri,
            relayed_by_actor: host,
            relay_activity_uri: @item.activity_uri,
            confirmed_at: @now,
            audience: "public",
            body: @value.body,
            content_html: @value.content_html,
            published_at: @value.published_at || @now,
            source_domain: Allure::Federation::Authority.domain(author.uri),
            raw: @value.raw,
            warnings: (@value.warnings + warnings).first(Parsers::RemoteComment::MAX_WARNINGS)
          )
        end
        Comments::Relink.call!(comment)
        Comments::Notifier.notify!(comment)
        comment
      rescue ActiveRecord::RecordNotUnique
        known_comment(::Comment.find_by!(uri: @value.object_uri), host)
      end

      def client = @client ||= Transport::Client.new
    end
  end
end
