# frozen_string_literal: true

module Comments
  # One target's thread as a viewer reads it (PLAN_COMMENTS.md §5.5): roots in
  # posting order, each with its replies in posting order, authors and their
  # avatars preloaded in the same pass. Active comments show to everyone; a
  # withdrawn root that still has visible replies stays as a stub so the
  # replies keep their context; the viewer's own removed or refused comments
  # show to that viewer only, with their state. Everything else is hidden.
  class Listing
    Entry = Data.define(:comment, :replies, :stub) do
      def stub? = stub
    end

    Result = Data.define(:entries, :active_count) do
      def empty? = entries.empty?
    end

    AUTHOR_PRELOAD = {
      actor: [ { user: %i[avatar_attachment gravatar_cache_attachment] }, :avatar_cache_attachment ]
    }.freeze

    # `viewer` is the reading account's actor, or nil. `audiences` limits a
    # workout's thread to the audiences the reader may read
    # (Workouts::ReadableAudiences); nil reads them all.
    def initialize(target:, viewer: nil, audiences: nil)
      @target = target
      @viewer = viewer
      @audiences = audiences
    end

    def call
      scope = Comment.for_target(@target)
      scope = scope.where(audience: @audiences) if @audiences
      comments = scope.chronological.includes(AUTHOR_PRELOAD).to_a
      ids = comments.to_set(&:id)
      replies_by_parent = comments.select { |comment| comment.parent_id && ids.include?(comment.parent_id) }
        .group_by(&:parent_id)
      roots = comments.reject { |comment| comment.parent_id && ids.include?(comment.parent_id) }

      entries = roots.filter_map do |root|
        replies = Array(replies_by_parent[root.id]).select { |reply| visible?(reply) }
        if visible?(root)
          Entry.new(comment: root, replies:, stub: false)
        elsif replies.any?
          Entry.new(comment: root, replies:, stub: true)
        end
      end
      Result.new(entries:, active_count: comments.count(&:active?))
    end

    private

    def visible?(comment)
      comment.active? || own_withdrawn?(comment)
    end

    def own_withdrawn?(comment)
      @viewer.present? && comment.actor_id == @viewer.id && (comment.removed? || comment.rejected?)
    end
  end
end
