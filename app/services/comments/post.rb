# frozen_string_literal: true

module Comments
  # The single local write seam for comments (PLAN_COMMENTS.md §5.1). One post
  # authorizes the thread, normalizes the text, resolves the wire parent — the
  # parent comment, else the publication active right now or the received
  # note — and stores the row with its outbound intent and its notifications
  # in one transaction. On a workout, each publication audience keeps its own
  # thread (docs/dev/PUBLISHING.md): a reply joins its comment's audience, a new
  # comment the one of the publication serving the writer — the narrowest, or
  # the one the owner picks. A comment on a received note goes to its origin; the
  # owner's own comment goes to the publication's recipients; anyone else's
  # comment on a public workout here is relayed to them by the owner. A queue
  # failure after commit never rolls the comment back: the recovery sweep owns
  # pending events.
  class Post
    class NotAllowed < StandardError; end
    class Closed < StandardError; end

    class Invalid < StandardError
      REASONS = %i[blank too_long parent full].freeze

      attr_reader :reason

      def initialize(reason)
        @reason = reason
        super("comment is invalid: #{reason}")
      end
    end

    # C0 controls other than tab and newline, and DEL: invisible in the thread,
    # and NUL is not storable at all.
    CONTROL_CHARACTERS = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/

    # :allowed, :closed (the viewer may read the thread but comments are
    # closed), or :denied. The card and the write path share this answer.
    # `audience:` asks about one audience's thread of a workout.
    def self.permission(user:, target:, audience: nil)
      return :denied unless user

      case target
      when Workout then workout_permission(user, target, audience)
      when RemoteNote then note_permission(user, target)
      else :denied
      end
    end

    # The publication a writer's comment hangs on: the one of `audience`, or
    # the narrowest serving them.
    def self.publication_for(user:, workout:, audience: nil)
      Workouts::PublicationResolver.new(workout:, user:, audience:).call
    end

    def self.workout_permission(user, workout, audience)
      publication = publication_for(user:, workout:, audience:)
      return :denied unless publication

      policy = Workouts::PublicationPolicy.new(
        publication:,
        principal: Workouts::PublicationPrincipal.browser(user)
      )
      return :denied unless policy.allowed?(resource: :workout)

      policy.allowed?(resource: :comment) ? :allowed : :closed
    end
    private_class_method :workout_permission

    # A received note's thread is its origin's: readable through the note's
    # policy, writable unless the origin's profile closed it (§4.2). A thread
    # the origin closed live is only learnt from its refusal.
    def self.note_permission(user, note)
      return :denied unless Allure::Federation::Config.enabled?

      policy = Federation::RemoteNotePolicy.new(note:, principal: Workouts::PublicationPrincipal.browser(user))
      return :denied unless policy.allowed?(resource: :note)

      policy.allowed?(resource: :comment) ? :allowed : :closed
    end
    private_class_method :note_permission

    # Line endings become newlines, invisible controls go, runs of blank lines
    # collapse to one, and the text is trimmed of every kind of space.
    def self.normalize(value)
      value.to_s.dup.force_encoding(Encoding::UTF_8).scrub("")
        .gsub(/\r\n?/, "\n")
        .gsub(CONTROL_CHARACTERS, "")
        .gsub(/\n{3,}/, "\n\n")
        .gsub(/\A[[:space:]]+|[[:space:]]+\z/, "")
    end

    # `audience:` is the owner's choice of thread for a new comment; a reply
    # always joins its comment's audience.
    def initialize(user:, target:, body:, parent_id: nil, audience: nil, now: Time.current)
      @user = user
      @target = target
      @body = body
      @parent_id = parent_id.presence
      @audience = audience.presence
      @now = now
    end

    def call!
      raise NotAllowed, "the thread is not available" if self.class.permission(user: @user, target: @target) == :denied

      parent = resolve_parent
      case self.class.permission(user: @user, target: @target, audience: requested_audience(parent))
      when :denied then raise NotAllowed, "the thread is not available"
      when :closed then raise Closed, "comments are closed"
      end

      body = self.class.normalize(@body)
      raise Invalid.new(:blank) if body.empty?
      raise Invalid.new(:too_long) if body.length > Comment::MAX_BODY_LENGTH
      raise Invalid.new(:full) if Comment.for_target(@target).active.count >= Comment::MAX_ACTIVE_PER_THREAD

      @publication = self.class.publication_for(user: @user, workout: @target, audience: requested_audience(parent)) unless note?

      event = relayed = nil
      comment = Comment.transaction do
        comment = Comment.create!(
          actor:,
          **thread_attributes,
          parent:,
          in_reply_to_uri: parent ? parent.uri : thread_object_uri,
          audience: thread_audience,
          body:,
          published_at: @now
        )
        event = outbound_create(comment)
        comment.update!(activity_uri: event.activity_uri) if event
        relayed = outbound_relay(comment)
        Comments::Notifier.notify!(comment)
        comment
      end
      Comments::Outbound.enqueue!(event, relayed)
      comment
    end

    private

    def note? = @target.is_a?(RemoteNote)

    attr_reader :publication

    # Only the owner picks a thread; anyone else writes where they are served.
    def requested_audience(parent)
      return if note?
      return parent.audience if parent

      @audience if owner?
    end

    def thread_attributes = note? ? { remote_note: @target } : { workout: @target }

    def thread_object_uri = note? ? @target.object_uri : publication.object_uri

    def thread_audience = note? ? @target.audience : publication.audience

    def owner? = !note? && @target.user_id == @user.id

    # A reader's comment is sent to the received note's origin; the owner's
    # comment travels to the publication's recipients (PLAN_COMMENTS.md §8).
    def outbound_create(comment)
      return Federation::Outbox::CommentCreate.new(comment:).call! if note?
      return unless owner?

      Federation::Outbox::CommentCreate.new(comment:, publication:).call!
    end

    # Another member's comment on a public workout here is relayed by the
    # owner to the publication's recipients (§6.6). The row keeps no activity
    # URI of its own: the Announce is found by its deterministic one.
    def outbound_relay(comment)
      return if note? || owner? || publication.audience != "public"

      Federation::Outbox::CommentAnnounce.new(comment:, publication:).call!
    end

    def actor
      @actor ||= Federation::ActorProvisioner.new(user: @user).call!
    rescue Federation::ActorProvisioner::IdentityConflict
      raise NotAllowed, "the account has no usable actor"
    end

    # A reply answers an active top-level comment of the same thread; nothing
    # answers a reply (one level, PLAN_COMMENTS.md §1).
    def resolve_parent
      return unless @parent_id

      uuid = Allure::ShortId.decode(@parent_id)
      parent = readable_thread.find_by(uuid:)
      raise Invalid.new(:parent) unless parent&.active? && !parent.reply?

      parent
    rescue ArgumentError
      raise Invalid.new(:parent)
    end

    def readable_thread
      scope = Comment.for_target(@target)
      return scope if note?

      scope.where(audience: Workouts::ReadableAudiences.for(user: @user, workout: @target))
    end
  end
end
