# frozen_string_literal: true

module Comments
  # Takes every active comment of some actors out of their threads at once,
  # with the notices those comments caused (PLAN_COMMENTS.md §7.6): a local or
  # remote account deletion, or a block. An author whose account is gone takes
  # their words along — the rows keep their identity, and the Creates this
  # instance sent for them are redacted — while a block only takes the
  # comments out. A thread hosted here stops relaying them; those Undos are
  # left on `outbox_events` for the caller to expand after its commit.
  # Nothing is restored afterwards: the removal is the record.
  class AuthorRemoval
    SCRUBBING_REASONS = %w[actor_deleted].freeze

    attr_reader :outbox_events

    def initialize(actors:, reason:, now: Time.current)
      @actors = actors
      @reason = reason
      @now = now
      @outbox_events = []
    end

    def call!
      ids = Comment.active.where(actor: @actors).pluck(:id)
      return 0 if ids.empty?

      uris = Comment.where(id: ids).pluck(:uri)
      hosted = Comment.where(id: ids).where.not(workout_id: nil).to_a
      attributes = { status: "removed", removal_reason: @reason, removed_at: @now, updated_at: @now }
      attributes.merge!(Comment.scrubbed_text) if scrubbing?
      Comment.where(id: ids).update_all(attributes)
      Notification.where(kind: Comments::Notifier::KIND, subject_type: "Comment", subject_id: ids).delete_all
      redact_creates(uris) if scrubbing?
      hosted.each { |comment| unannounce(comment) }
      ids.size
    end

    private

    def scrubbing? = SCRUBBING_REASONS.include?(@reason)

    def redact_creates(uris)
      FederationOutboxEvent.where(activity_type: "Create", object_uri: uris).find_each do |event|
        ::Federation::Outbox::PayloadRedactor.new(event:, now: @now).call!
      end
    end

    def unannounce(comment)
      event = ::Federation::Outbox::CommentUnannounce.new(comment:, now: @now).call!
      @outbox_events << event if event
    end
  end
end
